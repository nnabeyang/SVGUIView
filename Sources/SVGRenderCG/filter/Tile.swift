import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Repeats the rectangle `tile` of the input of a `feTile` in x and y from its origin, and draws the result clipped
  /// to the subregion into `cgContext`.
  ///
  /// The part of the tile outside the filter region is transparent black, and a tile without pixels draws nothing.
  /// The pixels are copied as they are, without a conversion of the color space.
  func tile(
    _ tile: CGRect, input: SVGFilterInput?, srcImage: CGImage, inImage: CGImage, subregion: CGRect,
    bitmapRect: CGRect, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    // The pixels are copied as 4 bytes, which they are in the bitmaps of the filter.
    guard srcImage.bitsPerPixel == 32,
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
    else { return nil }
    // `inputImage` swaps the buffers, so free each allocation through the pointer that it returns.
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format) else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    guard
      let selected = inputImage(
        input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer),
      let source = try? vImage_Buffer(cgImage: selected, format: format)
    else { return nil }
    defer { source.free() }
    // The edges of the tile in pixels, from the left and from the top of the bitmap, whose rows start at the top.
    let left = Int(((tile.minX - bitmapRect.minX) * scale).rounded())
    let right = Int(((tile.maxX - bitmapRect.minX) * scale).rounded())
    let top = Int(((bitmapRect.maxY - tile.maxY) * scale).rounded())
    let bottom = Int(((bitmapRect.maxY - tile.minY) * scale).rounded())
    guard right > left, bottom > top else { return cgContext.makeImage() }
    guard let output = Self.tiled(source, left: left, top: top, width: right - left, height: bottom - top) else {
      return nil
    }
    defer { output.free() }
    guard let image = try? output.createCGImage(format: format) else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// A buffer of the size of `source` that repeats the rectangle of `source` at `left` and `top` of `width` by
  /// `height` pixels, which is transparent black where it's outside `source`.
  private static func tiled(_ source: vImage_Buffer, left: Int, top: Int, width: Int, height: Int) -> vImage_Buffer? {
    let columns = Int(source.width)
    let rows = Int(source.height)
    guard let output = try? vImage_Buffer(width: columns, height: rows, bitsPerPixel: 32) else { return nil }
    let bytesPerPixel = 4
    // The column and the row of `source` that each column and row of the output copies, or `nil` outside `source`.
    func sourceIndex(_ index: Int, origin: Int, size: Int, count: Int) -> Int? {
      let remainder = (index - origin) % size
      let tiled = origin + (remainder < 0 ? remainder + size : remainder)
      return (0..<count).contains(tiled) ? tiled : nil
    }
    let sourceColumns = (0..<columns).map { sourceIndex($0, origin: left, size: width, count: columns) }
    for y in 0..<rows {
      let row = output.data.advanced(by: y * output.rowBytes)
      guard let sourceY = sourceIndex(y, origin: top, size: height, count: rows) else {
        memset(row, 0, columns * bytesPerPixel)
        continue
      }
      let sourceRow = source.data.advanced(by: sourceY * source.rowBytes)
      for (x, sourceX) in sourceColumns.enumerated() {
        if let sourceX {
          memcpy(row.advanced(by: x * bytesPerPixel), sourceRow.advanced(by: sourceX * bytesPerPixel), bytesPerPixel)
        } else {
          memset(row.advanced(by: x * bytesPerPixel), 0, bytesPerPixel)
        }
      }
    }
    return output
  }
}
