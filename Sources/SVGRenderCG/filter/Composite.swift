import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Composites the first input of a `feComposite` with the second in the color space of the primitive, and draws the
  /// result clipped to the subregion into `cgContext`.
  ///
  /// The pixels are computed here rather than by the blend modes of Core Graphics, which would composite them in the
  /// color space of the bitmap of the filter.
  func composite(
    _ compositeOperator: SVGCompositeOperator, k: [Float], input: SVGFilterInput?, input2: SVGFilterInput?,
    colorSpace: SVGColorInterpolation, srcImage: CGImage, inImage: CGImage, subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    // The pixels are blue, green, red and alpha in memory, with the alpha premultiplied, so that the loop below knows
    // where each component is whatever the format of the images.
    guard k.count == 4,
      var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace,
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)),
      let buffer1 = inputBuffer(input, format: format, srcImage: srcImage, inImage: inImage, results: results)
    else { return nil }
    defer { buffer1.free() }
    guard let buffer2 = inputBuffer(input2, format: format, srcImage: srcImage, inImage: inImage, results: results)
    else { return nil }
    defer { buffer2.free() }
    guard buffer1.width == buffer2.width, buffer1.height == buffer2.height,
      var output = try? vImage_Buffer(width: Int(buffer1.width), height: Int(buffer1.height), bitsPerPixel: 32)
    else { return nil }
    defer { output.free() }
    Self.composite(buffer1, buffer2, into: output, compositeOperator, k: k)
    // The image uses the memory of the buffer, which is freed after the image is drawn below.
    guard
      let image = vImageCreateCGImageFromBuffer(
        &output, &format, { _, _ in }, nil, vImage_Flags(kvImageNoAllocate), nil)?.takeRetainedValue()
    else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// Composites the pixels of `a` with those of `b`, all premultiplied, into `destination` of the same size.
  private static func composite(
    _ a: vImage_Buffer, _ b: vImage_Buffer, into destination: vImage_Buffer, _ compositeOperator: SVGCompositeOperator,
    k: [Float]
  ) {
    let width = Int(a.width)
    for y in 0..<Int(a.height) {
      let rowA = a.data.advanced(by: y * a.rowBytes).assumingMemoryBound(to: UInt8.self)
      let rowB = b.data.advanced(by: y * b.rowBytes).assumingMemoryBound(to: UInt8.self)
      let row = destination.data.advanced(by: y * destination.rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        func pixel(_ row: UnsafeMutablePointer<UInt8>) -> SIMD4<Float> {
          SIMD4(Float(row[x * 4]), Float(row[x * 4 + 1]), Float(row[x * 4 + 2]), Float(row[x * 4 + 3])) / 255
        }
        let pixelA = pixel(rowA)
        let pixelB = pixel(rowB)
        let alphaA = pixelA[3]
        let alphaB = pixelB[3]
        // Porter-Duff, with the factors of the first input and of the second.
        var result: SIMD4<Float>
        switch compositeOperator {
        case .over: result = pixelA + pixelB * (1 - alphaA)
        case .in: result = pixelA * alphaB
        case .out: result = pixelA * (1 - alphaB)
        case .atop: result = pixelA * alphaB + pixelB * (1 - alphaA)
        case .xor: result = pixelA * (1 - alphaB) + pixelB * (1 - alphaA)
        case .arithmetic:
          result = k[0] * pixelA * pixelB + k[1] * pixelA + k[2] * pixelB + SIMD4(repeating: k[3])
          result = result.clamped(lowerBound: .zero, upperBound: .one)
          // The result is premultiplied, so a color can't be more than its alpha.
          let alpha = result[3]
          result = SIMD4(min(result[0], alpha), min(result[1], alpha), min(result[2], alpha), alpha)
        }
        let pixel = row + x * 4
        for i in 0..<4 {
          pixel[i] = UInt8((min(max(result[i], 0), 1) * 255).rounded())
        }
      }
    }
  }
}
