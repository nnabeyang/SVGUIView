import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Draws an image, clipped by its clip. A bitmap is drawn in its rectangle, with its pixels as they're stored,
  /// without the orientation in the image's metadata, as `UIImage.cgImage` gives them. An SVG image is painted as a
  /// render tree, whose root places it.
  func paintImage(_ paint: ImagePaint, graphics: CGContext) async {
    graphics.saveGState()
    defer { graphics.restoreGState() }
    if let clip = paint.clip {
      graphics.clip(to: clip)
    }
    switch paint.content {
    case .bitmap(let image):
      let rect = paint.rect
      graphics.scaleBy(x: 1, y: -1)
      graphics.draw(image, in: CGRect(x: rect.minX, y: -rect.height - rect.minY, width: rect.width, height: rect.height))
    case .document(let root):
      await self.paint(root, into: graphics, isClipped: paint.clip != nil)
    }
  }
}
