import CoreGraphics
import Foundation
import SVGCore

/// Draws an image in its rectangle, clipped by its clip. The pixels are drawn as they're stored, without the
/// orientation in the image's metadata, as `UIImage.cgImage` gives them.
func paintImage(_ paint: ImagePaint, graphics: CGContext) {
  graphics.saveGState()
  defer { graphics.restoreGState() }
  if let clip = paint.clip {
    graphics.clip(to: clip)
  }
  let rect = paint.rect
  graphics.scaleBy(x: 1, y: -1)
  graphics.draw(paint.image, in: CGRect(x: rect.minX, y: -rect.height - rect.minY, width: rect.width, height: rect.height))
}
