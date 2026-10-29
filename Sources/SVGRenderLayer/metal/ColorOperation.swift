import Accelerate
import CoreGraphics
import Foundation
import SVGCore

/// An operation of Core Graphics or vImage on the premultiplied pixels of a filter, which `MetalFilterRenderer` looks up
/// in a table, so that it rounds as the filters on the CPU do.
///
/// Each operation changes each component of a pixel by itself and its alpha, so a table of all the components and
/// alphas holds what the operation does to any pixel.
enum ColorOperation: Hashable, Sendable {
  /// vImage converting an image of a color space into a buffer of another.
  case convert(from: SVGColorInterpolation, to: SVGColorInterpolation)
  /// Core Graphics drawing an image of a color space with an alpha into a cleared bitmap of another.
  case draw(from: SVGColorInterpolation, to: SVGColorInterpolation, alpha: CGFloat)

  /// The size in bytes of a table.
  static let tableSize = 256 * 256 * 2

  /// For each alpha and component, the component and the alpha after the operation, at `(alpha * 256 + component) * 2`,
  /// or `nil` if the bitmaps can't be made.
  var table: [UInt8]? {
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    // Each row is an alpha, and each column a component of all the colors, which can't exceed the alpha.
    var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
    for alpha in 0..<256 {
      for component in 0..<256 {
        let index = (alpha * 256 + component) * 4
        let value = UInt8(min(component, alpha))
        pixels[index] = value
        pixels[index + 1] = value
        pixels[index + 2] = value
        pixels[index + 3] = UInt8(alpha)
      }
    }
    let from: SVGColorInterpolation =
      switch self {
      case .convert(let from, _), .draw(let from, _, _): from
      }
    guard
      let image = pixels.withUnsafeMutableBytes({ bytes in
        CGContext(
          data: bytes.baseAddress, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4,
          space: from.colorSpace, bitmapInfo: bitmapInfo)?.makeImage()
      })
    else { return nil }
    var result = [UInt8](repeating: 0, count: 256 * 256 * 4)
    switch self {
    case .convert(_, let to):
      guard
        let format = vImage_CGImageFormat(
          bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: to.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo)),
        let buffer = try? vImage_Buffer(cgImage: image, format: format)
      else { return nil }
      defer { buffer.free() }
      result.withUnsafeMutableBytes { bytes in
        for row in 0..<256 {
          bytes.baseAddress!.advanced(by: row * 256 * 4).copyMemory(
            from: buffer.data.advanced(by: row * buffer.rowBytes), byteCount: 256 * 4)
        }
      }
    case .draw(_, let to, let alpha):
      let drawn = result.withUnsafeMutableBytes { bytes -> Bool in
        guard
          let context = CGContext(
            data: bytes.baseAddress, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4,
            space: to.colorSpace, bitmapInfo: bitmapInfo)
        else { return false }
        context.setAlpha(alpha)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        return true
      }
      guard drawn else { return nil }
    }
    var table = [UInt8](repeating: 0, count: Self.tableSize)
    for index in 0..<(256 * 256) {
      table[index * 2] = result[index * 4]
      table[index * 2 + 1] = result[index * 4 + 3]
    }
    return table
  }
}
