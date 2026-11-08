import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Convolves the input of a `feConvolveMatrix` with its kernel in the color space of the primitive, and draws the
  /// result clipped to the subregion into `cgContext`, or returns `nil` if its bitmaps can't be made or the task is
  /// cancelled.
  ///
  /// A cell of the kernel is a pixel of the bitmap, the default of `kernelUnitLength`, which isn't supported. The
  /// kernel is rotated by 180 degrees over each pixel, as the specification gives, and the components are
  /// premultiplied unless `preserveAlpha` keeps the alpha. The bias is added to each component, as Chrome, Firefox
  /// and Safari add it, instead of the bias times the alpha that the formula of Filter Effects 1 gives. As in the
  /// browsers, a pixel that the kernel finds no alpha around stays transparent, instead of getting the bias. A
  /// primitive in error is transparent black.
  func convolveMatrix(
    _ matrix: ConvolveMatrixPrimitive?, input: SVGFilterInput?, colorSpace: SVGColorInterpolation, srcImage: CGImage,
    inImage: CGImage, subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    guard let matrix else {
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
    // The components from 0 to 1, in the order of the pixels: blue, green, red and alpha, with the colors
    // premultiplied unless the alpha is preserved.
    var components = [Float](repeating: 0, count: width * height * 4)
    for row in 0..<height {
      let pixels = source.data.advanced(by: row * source.rowBytes).assumingMemoryBound(to: UInt8.self)
      for column in 0..<width {
        let index = (row * width + column) * 4
        let alpha = Float(pixels[column * 4 + 3])
        components[index + 3] = alpha / 255
        for c in 0..<3 {
          let value = Float(pixels[column * 4 + c])
          components[index + c] = matrix.preserveAlpha ? (alpha > 0 ? min(value / alpha, 1) : 0) : value / 255
        }
      }
    }
    let columns = matrix.columns
    let rows = matrix.rows
    for row in 0..<height {
      guard !Task.isCancelled else { return nil }
      let pixels = destination.data.advanced(by: row * destination.rowBytes).assumingMemoryBound(to: UInt8.self)
      for column in 0..<width {
        var sum = SIMD4<Float>.zero
        // Whether a pixel under the kernel has alpha.
        var hasAlpha = false
        for oy in 0..<rows {
          // The rows of the bitmap go down from the top, and y in the user space goes up from its bottom, so the rows
          // of the kernel go up the bitmap.
          var y = row + matrix.targetY - oy
          for ox in 0..<columns {
            var x = column - matrix.targetX + ox
            switch matrix.edgeMode {
            case .none:
              guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
            case .duplicate:
              x = min(max(x, 0), width - 1)
              y = min(max(y, 0), height - 1)
            case .wrap:
              x = ((x % width) + width) % width
              y = ((y % height) + height) % height
            }
            let k = matrix.kernel[(rows - oy - 1) * columns + (columns - ox - 1)]
            let index = (y * width + x) * 4
            hasAlpha = hasAlpha || components[index + 3] > 0
            sum +=
              k
              * SIMD4(components[index], components[index + 1], components[index + 2], components[index + 3])
          }
        }
        let index = (row * width + column) * 4
        // Without alpha around the pixel, the bias doesn't make it visible.
        guard matrix.preserveAlpha || hasAlpha else {
          for c in 0..<4 {
            pixels[column * 4 + c] = 0
          }
          continue
        }
        let alpha = matrix.preserveAlpha ? components[index + 3] : sum[3] / matrix.divisor + matrix.bias
        let boundedAlpha = min(max(alpha, 0), 1)
        for c in 0..<3 {
          let value = sum[c] / matrix.divisor + matrix.bias
          let color = matrix.preserveAlpha ? min(max(value, 0), 1) * boundedAlpha : min(max(value, 0), boundedAlpha)
          pixels[column * 4 + c] = UInt8((color * 255).rounded())
        }
        pixels[column * 4 + 3] = UInt8((boundedAlpha * 255).rounded())
      }
    }
    guard let convolved = try? destination.createCGImage(format: format) else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(convolved, in: bitmapRect)
    return cgContext.makeImage()
  }
}
