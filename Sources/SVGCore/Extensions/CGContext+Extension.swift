import CoreGraphics

extension CGContext {
  /// Makes a bitmap context of premultiplied 32-bit pixels to render a size in points into.
  ///
  /// - Returns: The context, or `nil` if the size has no pixel or the bitmap is too large to allocate.
  package static func bitmap(size: CGSize, scale: CGFloat, space: CGColorSpace) -> CGContext? {
    guard let (pixelWidth, pixelHeight, bytesPerRow) = bitmapLayout(size: size, scale: scale) else { return nil }
    return CGContext(
      data: nil,
      width: pixelWidth,
      height: pixelHeight,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
  }

  /// The width and height in pixels and the bytes per row of a bitmap of a size in points, or `nil` if the size has
  /// no pixel or doesn't fit in `Int`, in which case `bitmap(size:scale:space:)` makes no bitmap.
  static func bitmapLayout(size: CGSize, scale: CGFloat) -> (width: Int, height: Int, bytesPerRow: Int)? {
    let width = (size.width * scale).rounded(.up)
    let height = (size.height * scale).rounded(.up)
    // A size that does not fit in `Int` is too large for a bitmap anyway.
    guard width > 0, height > 0, let pixelWidth = Int(exactly: width), let pixelHeight = Int(exactly: height) else {
      return nil
    }
    let (bytesPerRow, overflow) = pixelWidth.multipliedReportingOverflow(by: 4)
    guard !overflow else { return nil }
    return (pixelWidth, pixelHeight, bytesPerRow)
  }
}
