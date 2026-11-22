import CoreGraphics
import Foundation
import ImageIO
import SVGCore

extension CGPainter {
  /// Draws an image, clipped by its clip. A bitmap is drawn in its rectangle, turned by its orientation, and
  /// interpolated unless its paint says otherwise. An SVG image is painted as a render tree, whose root places it.
  func paintImage(_ paint: ImagePaint, graphics: CGContext) async {
    graphics.saveGState()
    defer { graphics.restoreGState() }
    if let clip = paint.clip {
      graphics.clip(to: clip)
    }
    switch paint.content {
    case .bitmap(let image, let orientation):
      let rect = paint.rect
      if !paint.interpolates {
        graphics.interpolationQuality = .none
      }
      if orientation == .up {
        graphics.scaleBy(x: 1, y: -1)
        graphics.draw(
          image, in: CGRect(x: rect.minX, y: -rect.height - rect.minY, width: rect.width, height: rect.height))
      } else {
        // The unit square of the rectangle, from the top left, takes the unit square of the stored pixels, from
        // their top left, turned by the orientation, and the image is drawn upside down in it, as Core Graphics
        // draws an image from the bottom up.
        graphics.translateBy(x: rect.minX, y: rect.minY)
        graphics.scaleBy(x: rect.width, y: rect.height)
        graphics.concatenate(Self.transform(of: orientation))
        graphics.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1))
        graphics.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      }
    case .document(let root):
      await self.paint(root, into: graphics, isClipped: paint.clip != nil)
    }
  }

  /// The transform from the unit square of the stored pixels of an image to the unit square of the image turned by
  /// an orientation, both from the top left, as the EXIF orientation defines it.
  static func transform(of orientation: CGImagePropertyOrientation) -> CGAffineTransform {
    switch orientation {
    case .up: .identity
    case .upMirrored: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)
    case .down: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
    case .downMirrored: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
    case .leftMirrored: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
    case .right: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
    case .rightMirrored: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 1, ty: 1)
    case .left: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1)
    @unknown default: .identity
    }
  }
}
