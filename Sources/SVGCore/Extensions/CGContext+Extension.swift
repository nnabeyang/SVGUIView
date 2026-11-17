import CoreGraphics

extension CGColorSpace {
  private static let displayP3Space = CGColorSpace(name: CGColorSpace.displayP3)!

  /// The color space of the bitmaps that renderings are painted into: Display P3, which shows colors outside sRGB
  /// on a screen of a wide gamut, or device RGB, which is sRGB, as renderings were before they showed them.
  package static func rendering(wideGamut: Bool) -> CGColorSpace {
    wideGamut ? displayP3Space : CGColorSpaceCreateDeviceRGB()
  }
}

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
  package static func bitmapLayout(size: CGSize, scale: CGFloat) -> (width: Int, height: Int, bytesPerRow: Int)? {
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

  /// The rectangle that a bitmap of a rectangle in points covers: the rectangle, with its width and height rounded up
  /// to whole pixels at the scale, or the rectangle if it has no pixel.
  ///
  /// An image of the bitmap that's drawn into this rectangle, or that clips to it as a mask, is copied pixel for
  /// pixel rather than scaled a little. A bitmap of the size of this rectangle has the same pixels.
  package static func bitmapRect(of rect: CGRect, scale: CGFloat) -> CGRect {
    guard let (width, height, _) = bitmapLayout(size: rect.size, scale: scale) else { return rect }
    return bitmapRect(at: rect.origin, width: width, height: height, scale: scale)
  }

  /// The rectangle at a point that a bitmap of a width and a height in pixels covers at a scale. A bitmap of the size
  /// of the rectangle has the same pixels.
  package static func bitmapRect(at origin: CGPoint, width: Int, height: Int, scale: CGFloat) -> CGRect {
    /// The length of the pixels, which a bitmap of the length rounds up to the same pixels.
    func length(_ pixels: Int) -> CGFloat {
      var length = CGFloat(pixels) / scale
      while (length * scale).rounded(.up) > CGFloat(pixels) { length = length.nextDown }
      return length
    }
    return CGRect(x: origin.x, y: origin.y, width: length(width), height: length(height))
  }
}
