import Accelerate
import CoreGraphics
import Foundation
import SVGCore
import simd

extension CGPainter {
  /// Lights the surface of the alpha of the input of a `feDiffuseLighting` or a `feSpecularLighting` in the color
  /// space of the primitive, and draws the result clipped to the subregion into `cgContext`, or returns `nil` if its
  /// bitmaps can't be made or the task is cancelled.
  ///
  /// The normals of the surface come from the Sobel kernels of the specification over the pixels of the bitmap, the
  /// default of `kernelUnitLength`, which isn't supported. The diffuse reflection is opaque, and the specular one has
  /// the greatest of its colors as its alpha, which the colors are premultiplied by already, as in resvg and Chrome.
  /// A primitive in error is transparent black.
  func lighting(
    _ lighting: LightingPrimitive?, input: SVGFilterInput?, colorSpace: SVGColorInterpolation, srcImage: CGImage,
    inImage: CGImage, subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    guard let lighting else {
      // Transparent black, which the bitmap already is.
      return cgContext.makeImage()
    }
    let bitmapInfo = CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    guard
      let format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace, bitmapInfo: bitmapInfo),
      let source = inputBuffer(input, format: format, srcImage: srcImage, inImage: inImage, results: results)
    else { return nil }
    defer { source.free() }
    guard let destination = try? vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32)
    else { return nil }
    defer { destination.free() }
    let width = Int(source.width)
    let height = Int(source.height)
    // The alpha from 0 to 1, with the rows from the top of the user space, which is the bottom row of the bitmap, so
    // that y goes down as in the specification.
    var alpha = [Float](repeating: 0, count: width * height)
    for y in 0..<height {
      let pixels = source.data.advanced(by: (height - 1 - y) * source.rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        alpha[y * width + x] = Float(pixels[x * 4 + 3]) / 255
      }
    }
    // The light color in the color space of the primitive.
    var color = lighting.color
    if colorSpace == .linearRGB {
      for c in 0..<3 {
        let value = color[c]
        color[c] = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
    }
    // The origin of the bitmaps in the user space, their corner with the least coordinates.
    let origin = SIMD2(Float(bitmapRect.minX), Float(bitmapRect.minY))
    let light = LightSource(lighting.lightSource, origin: origin, scale: Float(scale))
    let surface = LightingSurface(alpha: alpha, width: width, height: height, scale: lighting.surfaceScale)
    // The loops are made for each kind of light and of reflection, so that a pixel decides neither.
    let isLit: Bool =
      switch (light.kind, lighting.reflection) {
      case (.distant(let vector), .diffuse(let constant)):
        surface.light(DistantLight(vector: vector), DiffuseReflection(constant: constant), color, into: destination)
      case (.distant(let vector), .specular(let constant, let exponent)):
        surface.light(
          DistantLight(vector: vector), SpecularReflection(constant: constant, exponent: exponent), color,
          into: destination)
      case (.point(let position), .diffuse(let constant)):
        surface.light(PointLight(position: position), DiffuseReflection(constant: constant), color, into: destination)
      case (.point(let position), .specular(let constant, let exponent)):
        surface.light(
          PointLight(position: position), SpecularReflection(constant: constant, exponent: exponent), color,
          into: destination)
      case (.spot(let spot), .diffuse(let constant)):
        surface.light(spot, DiffuseReflection(constant: constant), color, into: destination)
      case (.spot(let spot), .specular(let constant, let exponent)):
        surface.light(spot, SpecularReflection(constant: constant, exponent: exponent), color, into: destination)
      }
    guard isLit else { return nil }
    guard let lit = try? destination.createCGImage(format: format) else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(lit, in: bitmapRect)
    return cgContext.makeImage()
  }
}

/// The surface of the alpha of the input of a lighting primitive, with the rows from the top of the user space.
struct LightingSurface {
  let alpha: [Float]
  let width: Int
  let height: Int
  /// The `surfaceScale` of the primitive.
  let scale: Float

  /// Lights the surface into the destination, whose bottom row is the top of the user space, and returns whether it
  /// lit every row, or `false` if the task is cancelled.
  @inline(__always)
  fileprivate func light<Light: LightModel, Reflection: ReflectionModel>(
    _ light: Light, _ reflection: Reflection, _ color: SIMD3<Float>, into destination: vImage_Buffer
  ) -> Bool {
    for y in 0..<height {
      guard !Task.isCancelled else { return false }
      let pixels = destination.data.advanced(by: (height - 1 - y) * destination.rowBytes).assumingMemoryBound(
        to: UInt8.self)
      let isInnerRow = y > 0 && y < height - 1
      for x in 0..<width {
        let normal =
          isInnerRow && x > 0 && x < width - 1 ? innerNormal(x: x, y: y) : edgeNormal(x: x, y: y)
        // The point of the surface at the corner of the pixel with the least coordinates, as in resvg.
        let point = SIMD3(Float(x), Float(y), scale * alpha[y * width + x])
        let (direction, intensity) = light.light(at: point)
        var factor = reflection.factor(normal: normal, direction: direction)
        // An infinite factor, such as 0 to a negative exponent, stays finite, so that it times 0 is 0.
        factor = factor.isNaN ? 0 : min(factor, .greatestFiniteMagnitude)
        let rgb = ((simd_clamp(color * intensity * factor, .zero, .one)) * 255).rounded(.toNearestOrAwayFromZero)
        // Blue, green, red and alpha in memory.
        pixels[x * 4] = UInt8(rgb[2])
        pixels[x * 4 + 1] = UInt8(rgb[1])
        pixels[x * 4 + 2] = UInt8(rgb[0])
        pixels[x * 4 + 3] = UInt8(Reflection.alpha(of: rgb))
      }
    }
    return true
  }

  /// The unit normal of the surface at a pixel inside the edges, which has pixels on every side, as `edgeNormal`
  /// finds it there, with the same arithmetic.
  @inline(__always)
  func innerNormal(x: Int, y: Int) -> SIMD3<Float> {
    let above = (y - 1) * width + x
    let row = y * width + x
    let below = (y + 1) * width + x
    let weights = SIMD3<Float>(1, 2, 1)
    let dx = SIMD3(
      alpha[above + 1] - alpha[above - 1], alpha[row + 1] - alpha[row - 1], alpha[below + 1] - alpha[below - 1])
    let nx = -scale * 2 / 2 * (weights * dx).sum() / weights.sum()
    let dy = SIMD3(
      alpha[below - 1] - alpha[above - 1], alpha[below] - alpha[above], alpha[below + 1] - alpha[above + 1])
    let ny = -scale * 2 / 2 * (weights * dy).sum() / weights.sum()
    let normal = SIMD3(nx, ny, 1)
    return normal / (normal * normal).sum().squareRoot()
  }

  /// The unit normal of the surface at a pixel, from the Sobel kernels of the specification, which take the pixels
  /// on both sides where they're in the image and the pixel itself on an edge, and weigh the row or the column of
  /// the pixel twice as much as the ones beside it.
  func edgeNormal(x: Int, y: Int) -> SIMD3<Float> {
    func a(_ x: Int, _ y: Int) -> Float { alpha[y * width + x] }
    let left = max(x - 1, 0)
    let right = min(x + 1, width - 1)
    let top = max(y - 1, 0)
    let bottom = min(y + 1, height - 1)
    // The weights of the row or the column before the pixel, the pixel's own and the one after it, which are 0 past
    // the edges.
    let rowWeights = SIMD3<Float>(y > 0 ? 1 : 0, 2, y < height - 1 ? 1 : 0)
    let columnWeights = SIMD3<Float>(x > 0 ? 1 : 0, 2, x < width - 1 ? 1 : 0)
    var nx: Float = 0
    if right > left {
      let difference = SIMD3(a(right, top) - a(left, top), a(right, y) - a(left, y), a(right, bottom) - a(left, bottom))
      // The difference over the distance between the columns, in pixels, as the factors of the specification give.
      nx = -scale * 2 / Float(right - left) * (rowWeights * difference).sum() / rowWeights.sum()
    }
    var ny: Float = 0
    if bottom > top {
      let difference = SIMD3(a(left, bottom) - a(left, top), a(x, bottom) - a(x, top), a(right, bottom) - a(right, top))
      ny = -scale * 2 / Float(bottom - top) * (columnWeights * difference).sum() / columnWeights.sum()
    }
    let normal = SIMD3(nx, ny, 1)
    return normal / (normal * normal).sum().squareRoot()
  }
}

/// The light of a light source at the points of a surface.
private protocol LightModel {
  /// The unit vector from a point of the surface towards the light, and the intensity of the light there, which
  /// multiplies the lighting color.
  func light(at surface: SIMD3<Float>) -> (vector: SIMD3<Float>, intensity: Float)
}

/// How a surface reflects light.
private protocol ReflectionModel {
  /// The factor of the light that a point of the surface with the normal reflects.
  func factor(normal: SIMD3<Float>, direction: SIMD3<Float>) -> Float
  /// The alpha of a pixel of the colors.
  static func alpha(of rgb: SIMD3<Float>) -> Float
}

private struct DistantLight: LightModel {
  /// The unit vector towards the light.
  let vector: SIMD3<Float>

  @inline(__always)
  func light(at _: SIMD3<Float>) -> (vector: SIMD3<Float>, intensity: Float) {
    (vector, 1)
  }
}

private struct PointLight: LightModel {
  let position: SIMD3<Float>

  @inline(__always)
  func light(at surface: SIMD3<Float>) -> (vector: SIMD3<Float>, intensity: Float) {
    (normalized(position - surface), 1)
  }
}

private struct SpotLight: LightModel {
  let position: SIMD3<Float>
  /// The unit vector of the axis.
  let axis: SIMD3<Float>
  let exponent: Float
  /// The cosine of the cone, if any.
  let coneCosine: Float?

  /// The width of the cosines inside the edge of the cone of a spot light where its light fades out, as in WebKit
  /// and Chrome, so that the edge is smooth as the specification asks.
  static let antiAliasThreshold: Float = 0.016

  @inline(__always)
  func light(at surface: SIMD3<Float>) -> (vector: SIMD3<Float>, intensity: Float) {
    let vector = normalized(position - surface)
    let cosine = -(vector * axis).sum()
    guard cosine > 0 else { return (vector, 0) }
    var intensity = pow(cosine, exponent)
    if let coneCosine {
      guard cosine >= coneCosine else { return (vector, 0) }
      if cosine < coneCosine + Self.antiAliasThreshold {
        intensity *= (cosine - coneCosine) / Self.antiAliasThreshold
      }
    }
    return (vector, intensity)
  }
}

/// The diffuse reflection, which is opaque.
private struct DiffuseReflection: ReflectionModel {
  let constant: Float

  @inline(__always)
  func factor(normal: SIMD3<Float>, direction: SIMD3<Float>) -> Float {
    // A surface facing away from the light gets none of it, so that a negative constant lights nothing.
    constant * max((normal * direction).sum(), 0)
  }

  @inline(__always)
  static func alpha(of _: SIMD3<Float>) -> Float { 255 }
}

/// The specular reflection, whose alpha is the greatest of its colors, which the colors are premultiplied by.
private struct SpecularReflection: ReflectionModel {
  let constant: Float
  let exponent: Float

  @inline(__always)
  func factor(normal: SIMD3<Float>, direction: SIMD3<Float>) -> Float {
    let halfway = direction + SIMD3(0, 0, 1)
    let halfwayLength = (halfway * halfway).sum().squareRoot()
    let cosine = halfwayLength > 0 ? (normal * halfway).sum() / halfwayLength : 0
    return constant * pow(max(cosine, 0), exponent)
  }

  @inline(__always)
  static func alpha(of rgb: SIMD3<Float>) -> Float { rgb.max() }
}

/// A light source of a lighting primitive in the pixels of the bitmap of the filter, with y going down from the top
/// of the user space.
private struct LightSource {
  enum Kind {
    /// The unit vector towards the light.
    case distant(SIMD3<Float>)
    case point(SIMD3<Float>)
    case spot(SpotLight)
  }

  let kind: Kind

  /// The light source of positions in the user space, which moves to the pixels from the origin of the bitmap at
  /// the scale, with `z` at the scale too, as in resvg.
  init(_ source: LightingPrimitive.LightSource, origin: SIMD2<Float>, scale: Float) {
    func pixels(_ position: SIMD3<Float>) -> SIMD3<Float> {
      SIMD3((position.x - origin.x) * scale, (position.y - origin.y) * scale, position.z * scale)
    }
    switch source {
    case .distant(let azimuth, let elevation):
      let a = azimuth * .pi / 180
      let e = elevation * .pi / 180
      kind = .distant(SIMD3(cos(a) * cos(e), sin(a) * cos(e), sin(e)))
    case .point(let position):
      kind = .point(pixels(position))
    case .spot(let position, let pointsAt, let exponent, let angle):
      let start = pixels(position)
      kind = .spot(
        SpotLight(
          position: start, axis: normalized(pixels(pointsAt) - start), exponent: exponent,
          coneCosine: angle.map { cos($0 * .pi / 180) }))
    }
  }
}

/// The vector of length 1 in its direction, or the vector itself if it has no length.
@inline(__always)
private func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float> {
  let length = (vector * vector).sum().squareRoot()
  return length > 0 ? vector / length : vector
}
