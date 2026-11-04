import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Multiplies the colors of the input by the matrix of a `feColorMatrix` in the color space of the primitive, and
  /// draws the result into `cgContext`.
  func colorMatrix(
    _ matrix: [Float], input: SVGFilterInput?, colorSpace: SVGColorInterpolation, srcImage: CGImage,
    inImage: CGImage, subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    guard matrix.count == 20 else { return nil }
    return mapColors(
      input: input, colorSpace: colorSpace, srcImage: srcImage, inImage: inImage, subregion: subregion,
      bitmapRect: bitmapRect, cgContext: cgContext, results: results
    ) { color in
      func row(_ i: Int) -> Float {
        matrix[i * 5] * color[0] + matrix[i * 5 + 1] * color[1] + matrix[i * 5 + 2] * color[2] + matrix[i * 5 + 3]
          * color[3] + matrix[i * 5 + 4]
      }
      return SIMD4(row(0), row(1), row(2), row(3))
    }
  }

  /// Maps the components of the input by the transfer functions of a `feComponentTransfer` in the color space of the
  /// primitive, and draws the result into `cgContext`.
  func componentTransfer(
    _ functions: (red: TransferFunction, green: TransferFunction, blue: TransferFunction, alpha: TransferFunction),
    input: SVGFilterInput?, colorSpace: SVGColorInterpolation, srcImage: CGImage, inImage: CGImage,
    subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext,
    results: [String: CGImage]
  ) -> CGImage? {
    mapColors(
      input: input, colorSpace: colorSpace, srcImage: srcImage, inImage: inImage, subregion: subregion,
      bitmapRect: bitmapRect, cgContext: cgContext, results: results
    ) { color in
      SIMD4(
        functions.red.apply(color[0]), functions.green.apply(color[1]), functions.blue.apply(color[2]),
        functions.alpha.apply(color[3]))
    }
  }

  /// Maps the color of each pixel of the input, converted to the color space of the primitive, and draws the result
  /// clipped to the subregion into `cgContext`.
  ///
  /// - Parameter map: The function from the red, green, blue and alpha of a pixel without its alpha premultiplied,
  ///   from 0 to 1, to those of the result, which are clamped to 0 to 1.
  private func mapColors(
    input: SVGFilterInput?, colorSpace: SVGColorInterpolation, srcImage: CGImage, inImage: CGImage,
    subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext,
    results: [String: CGImage], map: (SIMD4<Float>) -> SIMD4<Float>
  ) -> CGImage? {
    // The pixels are blue, green, red and alpha in memory, with the alpha premultiplied, so that the loop below knows
    // where each component is whatever the format of the images.
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace,
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)),
      let buffer = inputBuffer(input, format: format, srcImage: srcImage, inImage: inImage, results: results)
    else { return nil }
    defer { buffer.free() }
    guard var output = try? vImage_Buffer(width: Int(buffer.width), height: Int(buffer.height), bitsPerPixel: 32)
    else { return nil }
    defer { output.free() }
    Self.map(buffer, into: output, by: map)
    // The image uses the memory of the buffer, which is freed after the image is drawn below.
    guard
      let image = vImageCreateCGImageFromBuffer(
        &output, &format, { _, _ in }, nil, vImage_Flags(kvImageNoAllocate), nil)?.takeRetainedValue()
    else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// Maps the components of each pixel of `source`, blue, green, red and alpha with the alpha premultiplied, without
  /// the alpha premultiplied, and writes the result into `destination` of the same size.
  private static func map(
    _ source: vImage_Buffer, into destination: vImage_Buffer, by map: (SIMD4<Float>) -> SIMD4<Float>
  ) {
    let width = Int(source.width)
    for y in 0..<Int(source.height) {
      let from = source.data.advanced(by: y * source.rowBytes).assumingMemoryBound(to: UInt8.self)
      let to = destination.data.advanced(by: y * destination.rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let pixel = from + x * 4
        let alpha = Float(pixel[3]) / 255
        // A transparent pixel has no color, which the functions take as black.
        let unpremultiplied: (Float) -> Float = { alpha > 0 ? min($0 / 255 / alpha, 1) : 0 }
        let color = SIMD4(
          unpremultiplied(Float(pixel[2])), unpremultiplied(Float(pixel[1])), unpremultiplied(Float(pixel[0])), alpha)
        let mapped = map(color).clamped(lowerBound: .zero, upperBound: .one)
        func component(_ value: Float) -> UInt8 { UInt8((value * mapped[3] * 255).rounded()) }
        let result = to + x * 4
        result[0] = component(mapped[2])
        result[1] = component(mapped[1])
        result[2] = component(mapped[0])
        result[3] = UInt8((mapped[3] * 255).rounded())
      }
    }
  }
}
