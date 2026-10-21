import CoreGraphics
import Foundation

/// Draws an image in the bounds of a path, scaled to fit them. The pixels are drawn as they're stored, without the
/// orientation in the image's metadata, as `UIImage.cgImage` gives them.
///
/// The context stays flipped vertically afterwards.
func paintImage(_ image: CGImage, in path: CGPath, graphics: CGContext) {
  let bounds = path.boundingBoxOfPath
  let imageWidth = CGFloat(image.width)
  let imageHeight = CGFloat(image.height)
  let scale = fittingScale(width: bounds.width, height: bounds.height, imageSize: .init(width: imageWidth, height: imageHeight))
  let frame = CGRect(origin: bounds.origin, size: .init(width: imageWidth * scale, height: imageHeight * scale))
  graphics.scaleBy(x: 1, y: -1)
  graphics.draw(image, in: CGRect(x: frame.minX, y: -frame.height - frame.minY, width: frame.width, height: frame.height))
}

private func fittingScale(width: CGFloat, height: CGFloat, imageSize size: CGSize) -> CGFloat {
  let sx = width / size.width
  let sy = height / size.height
  if width == 0 { return sy }
  if height == 0 { return sx }
  return width > height ? sy : sx
}
