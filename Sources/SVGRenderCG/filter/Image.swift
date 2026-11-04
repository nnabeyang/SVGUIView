import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Draws what a `feImage` draws, an image or an element, into a bitmap of the filter region in the color space of
  /// the primitive, and draws it clipped to the subregion into `cgContext`, or returns `nil` if its bitmap can't be
  /// made or the task is cancelled.
  func image(
    _ image: ImagePrimitive?, colorSpace: SVGColorInterpolation, subregion: CGRect, bitmapRect: CGRect,
    cgContext: CGContext
  ) async -> CGImage? {
    guard let image else {
      // Transparent black, which the bitmap already is.
      return cgContext.makeImage()
    }
    let width = cgContext.width
    let height = cgContext.height
    guard
      let graphics = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace.colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
    else { return nil }
    // The bitmap covers the filter region at the scale, as the source of the filter does.
    graphics.concatenate(
      CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -bitmapRect.minX, y: -bitmapRect.minY))
    switch image {
    case .picture(let paint):
      await paintImage(paint, graphics: graphics)
    case .element(let node, let origin):
      graphics.translateBy(x: origin.x, y: origin.y)
      await paint(node, into: graphics)
    }
    guard !Task.isCancelled, let drawn = graphics.makeImage() else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(drawn, in: bitmapRect)
    return cgContext.makeImage()
  }
}
