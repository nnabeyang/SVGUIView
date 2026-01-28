import Accelerate
import UIKit

final class SVGFeOffsetElement: SVGElement, SVGFilterApplier {
  static var type: SVGElementName {
    .feOffset
  }

  var type: SVGElementName {
    .feOffset
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let dx: Double?
  let dy: Double?

  func style(with _: Stylesheet) -> any SVGElement {
    self
  }

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    dx = Double(attributes["dx", default: ""])
    dy = Double(attributes["dy", default: ""])
  }

  func apply(
    srcImage: CGImage, inImage: CGImage, clipRect: inout CGRect,
    filter: SVGFilterElement, frame: CGRect, effectRect: CGRect, opacity: CGFloat, cgContext: CGContext, context: SVGContext, results _: [String: CGImage], isFirst _: Bool
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format),
      let image = vImageCreateCGImageFromBuffer(
        &inputBuffer,
        &format,
        { _, _ in },
        nil,
        vImage_Flags(kvImageNoAllocate),
        nil)?.takeRetainedValue()
    else { return nil }
    let rect = self.frame(filter: filter, frame: frame, context: context)
    clipRect = CGRectIntersection(clipRect, rect)
    cgContext.clip(to: clipRect)
    let transform = transform(filter: filter, frame: frame)
    cgContext.concatenate(transform)
    cgContext.setAlpha(opacity)
    cgContext.draw(image, in: effectRect)
    return cgContext.makeImage()
  }

  func transform(filter: SVGFilterElement, frame: CGRect) -> CGAffineTransform {
    let primitiveUnits = filter.primitiveUnits ?? .userSpaceOnUse
    let dx = dx ?? 0
    let dy = dy ?? 0
    let x: CGFloat
    let y: CGFloat
    switch primitiveUnits {
    case .userSpaceOnUse:
      x = dx
      y = dy
    case .objectBoundingBox:
      x = dx * frame.width
      y = dy * frame.height
    }
    return CGAffineTransform(translationX: x, y: y)
  }
}

extension SVGFeOffsetElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
