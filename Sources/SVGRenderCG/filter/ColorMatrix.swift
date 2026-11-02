import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Multiplies the colors of the input by the matrix of a `feColorMatrix` in the color space of the primitive, and
  /// draws the result into `cgContext`.
  func colorMatrix(
    _ matrix: [Float], input: SVGFilterInput?, colorSpace: SVGColorInterpolation, srcImage: CGImage,
    inImage: CGImage, subregion: CGRect, clipRect: inout CGRect, bitmapRect: CGRect, opacity: CGFloat,
    cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    // The pixels are blue, green, red and alpha in memory, with the alpha premultiplied, so that the loop below knows
    // where each component is whatever the format of the images.
    guard matrix.count == 20,
      var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace,
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
    else { return nil }
    // The buffers convert the images to the format, and share memory below, so free each allocation once, through
    // the pointer that it returns.
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format) else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    guard let data = malloc(inputBuffer.rowBytes * Int(inputBuffer.height)) else { return nil }
    defer { free(data) }
    var buffer = vImage_Buffer(
      data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
    let resultData = inputImageBuffer(
      input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer,
      destBuffer: &buffer)
    defer { free(resultData) }
    guard var output = try? vImage_Buffer(width: Int(buffer.width), height: Int(buffer.height), bitsPerPixel: 32)
    else { return nil }
    defer { output.free() }
    Self.multiply(buffer, by: matrix, into: output)
    // The image uses the memory of the buffer, which is freed after the image is drawn below.
    guard
      let image = vImageCreateCGImageFromBuffer(
        &output, &format, { _, _ in }, nil, vImage_Flags(kvImageNoAllocate), nil)?.takeRetainedValue()
    else { return nil }
    clipRect = subregion
    cgContext.clip(to: subregion)
    cgContext.setAlpha(opacity)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// Multiplies the components of each pixel of `source`, blue, green, red and alpha with the alpha premultiplied, by
  /// the matrix without the alpha premultiplied, and writes the result into `destination` of the same size.
  package static func multiply(_ source: vImage_Buffer, by matrix: [Float], into destination: vImage_Buffer) {
    let width = Int(source.width)
    for y in 0..<Int(source.height) {
      let from = source.data.advanced(by: y * source.rowBytes).assumingMemoryBound(to: UInt8.self)
      let to = destination.data.advanced(by: y * destination.rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let pixel = from + x * 4
        let alpha = Float(pixel[3]) / 255
        // A transparent pixel has no color, which the matrix multiplies as black.
        let unpremultiplied: (Float) -> Float = { alpha > 0 ? min($0 / 255 / alpha, 1) : 0 }
        let red = unpremultiplied(Float(pixel[2]))
        let green = unpremultiplied(Float(pixel[1]))
        let blue = unpremultiplied(Float(pixel[0]))
        func row(_ i: Int) -> Float {
          let value =
            matrix[i * 5] * red + matrix[i * 5 + 1] * green + matrix[i * 5 + 2] * blue + matrix[i * 5 + 3] * alpha
            + matrix[i * 5 + 4]
          return min(max(value, 0), 1)
        }
        let resultAlpha = row(3)
        func component(_ value: Float) -> UInt8 { UInt8((value * resultAlpha * 255).rounded()) }
        let result = to + x * 4
        result[0] = component(row(2))
        result[1] = component(row(1))
        result[2] = component(row(0))
        result[3] = UInt8((resultAlpha * 255).rounded())
      }
    }
  }
}
