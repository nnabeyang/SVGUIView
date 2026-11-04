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
      var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace, bitmapInfo: bitmapInfo),
      let image = selectedImage(input, format: &format, srcImage: srcImage, inImage: inImage, results: results),
      let source = try? vImage_Buffer(cgImage: image, format: format),
      let destination = try? vImage_Buffer(width: image.width, height: image.height, bitsPerPixel: 32)
    else { return nil }
    defer {
      source.free()
      destination.free()
    }
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
    for y in 0..<height {
      guard !Task.isCancelled else { return nil }
      let pixels = destination.data.advanced(by: (height - 1 - y) * destination.rowBytes).assumingMemoryBound(
        to: UInt8.self)
      for x in 0..<width {
        let normal = Self.normal(x: x, y: y, alpha: alpha, width: width, height: height, scale: lighting.surfaceScale)
        // The point of the surface at the corner of the pixel with the least coordinates, as in resvg.
        let surface = SIMD3(Float(x), Float(y), lighting.surfaceScale * alpha[y * width + x])
        let (direction, intensity) = light.light(at: surface)
        let halfway = direction + SIMD3(0, 0, 1)
        let halfwayLength = (halfway * halfway).sum().squareRoot()
        var factor: Float
        switch lighting.reflection {
        case .diffuse(let constant):
          factor = constant * (normal * direction).sum()
        case .specular(let constant, let exponent):
          let cosine = halfwayLength > 0 ? (normal * halfway).sum() / halfwayLength : 0
          factor = constant * pow(max(cosine, 0), exponent)
        }
        // An infinite factor, such as 0 to a negative exponent, stays finite, so that it times 0 is 0.
        factor = factor.isNaN ? 0 : min(factor, .greatestFiniteMagnitude)
        let rgb = ((simd_clamp(color * intensity * factor, .zero, .one)) * 255).rounded(.toNearestOrAwayFromZero)
        let a: Float =
          switch lighting.reflection {
          case .diffuse: 255
          case .specular: rgb.max()
          }
        // Blue, green, red and alpha in memory.
        pixels[x * 4] = UInt8(rgb[2])
        pixels[x * 4 + 1] = UInt8(rgb[1])
        pixels[x * 4 + 2] = UInt8(rgb[0])
        pixels[x * 4 + 3] = UInt8(a)
      }
    }
    guard let lit = try? destination.createCGImage(format: format) else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(lit, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// The unit normal of the surface at a pixel, from the Sobel kernels of the specification, which take the pixels
  /// on both sides where they're in the image and the pixel itself on an edge, and weigh the row or the column of
  /// the pixel twice as much as the ones beside it.
  private static func normal(x: Int, y: Int, alpha: [Float], width: Int, height: Int, scale: Float) -> SIMD3<Float> {
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

/// A light source of a lighting primitive in the pixels of the bitmap of the filter, with y going down from the top
/// of the user space.
private struct LightSource {
  private enum Kind {
    /// The unit vector towards the light.
    case distant(SIMD3<Float>)
    case point(SIMD3<Float>)
    /// The unit vector of the axis, and the cosine of the cone, if any.
    case spot(position: SIMD3<Float>, axis: SIMD3<Float>, exponent: Float, coneCosine: Float?)
  }

  /// The width of the cosines inside the edge of the cone of a spot light where its light fades out, as in WebKit
  /// and Chrome, so that the edge is smooth as the specification asks.
  private static let antiAliasThreshold: Float = 0.016

  private let kind: Kind

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
        position: start, axis: Self.normalized(pixels(pointsAt) - start), exponent: exponent,
        coneCosine: angle.map { cos($0 * .pi / 180) })
    }
  }

  /// The unit vector from a point of the surface towards the light, and the intensity of the light there, which
  /// multiplies the lighting color.
  func light(at surface: SIMD3<Float>) -> (vector: SIMD3<Float>, intensity: Float) {
    switch kind {
    case .distant(let vector):
      return (vector, 1)
    case .point(let position):
      return (Self.normalized(position - surface), 1)
    case .spot(let position, let axis, let exponent, let coneCosine):
      let vector = Self.normalized(position - surface)
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

  /// The vector of length 1 in its direction, or the vector itself if it has no length.
  private static func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float> {
    let length = (vector * vector).sum().squareRoot()
    return length > 0 ? vector / length : vector
  }
}
