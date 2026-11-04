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
    let light: SIMD3<Float>
    switch lighting.lightSource {
    case .distant(let azimuth, let elevation):
      let a = azimuth * .pi / 180
      let e = elevation * .pi / 180
      light = SIMD3(cos(a) * cos(e), sin(a) * cos(e), sin(e))
    }
    let halfway = light + SIMD3(0, 0, 1)
    let halfwayLength = (halfway * halfway).sum().squareRoot()
    for y in 0..<height {
      guard !Task.isCancelled else { return nil }
      let pixels = destination.data.advanced(by: (height - 1 - y) * destination.rowBytes).assumingMemoryBound(
        to: UInt8.self)
      for x in 0..<width {
        let normal = Self.normal(x: x, y: y, alpha: alpha, width: width, height: height, scale: lighting.surfaceScale)
        var factor: Float
        switch lighting.reflection {
        case .diffuse(let constant):
          factor = constant * (normal * light).sum()
        case .specular(let constant, let exponent):
          let cosine = halfwayLength > 0 ? (normal * halfway).sum() / halfwayLength : 0
          factor = constant * pow(max(cosine, 0), exponent)
        }
        // An infinite factor, such as 0 to a negative exponent, stays finite, so that it times 0 is 0.
        factor = factor.isNaN ? 0 : min(factor, .greatestFiniteMagnitude)
        let rgb = ((simd_clamp(color * factor, .zero, .one)) * 255).rounded(.toNearestOrAwayFromZero)
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
