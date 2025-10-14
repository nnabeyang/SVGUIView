import Accelerate
import UIKit

struct SVGFeFloodElement: SVGElement, SVGFilterApplier {
  private static let maxKernelSize: UInt32 = 100
  var type: SVGElementName {
    .feFlood
  }

  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let floodColor: (any SVGUIColor)?
  let floodOpacity: Double?

  func style(with _: CSSStyle, at _: Int) -> any SVGElement {
    self
  }

  init(attributes: [String: String]) {
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    floodColor = Self.parseColor(description: attributes["flood-color", default: ""])
    floodOpacity = Double(attributes["flood-opacity", default: ""])
  }

  private static func parseColor(description: String) -> (any SVGUIColor)? {
    var data = description
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanColor()
    }
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
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format)
    else { return nil }
    let floodColor = floodColor ?? SVGColorName(name: "black")
    let floodOpacity = floodOpacity ?? 1.0
    let (red:r, green:g, blue:b, alpha:a) = floodColor.rgba

    let y = (r * 0.2125 + g * 0.7154 + b * 0.0721) * floodOpacity
    let u = (r * -0.115 + g * -0.386 + b * 0.5) * floodOpacity
    let v = (r * 0.5 + g * -0.454 + b * -0.046) * floodOpacity
    var color = [
      UInt8(round(y + u * 1.8558)),
      UInt8(round(y + u * -0.187 + v * -0.4678)),
      UInt8(round(y + v * 1.575)),
      UInt8((a * floodOpacity).rounded(.toNearestOrAwayFromZero)),
    ]
    vImageBufferFill_ARGB8888(
      &inputBuffer,
      &color,
      vImage_Flags(kvImageNoFlags))

    guard
      let image = vImageCreateCGImageFromBuffer(
        &inputBuffer,
        &format,
        { _, _ in },
        nil,
        vImage_Flags(kvImageNoAllocate),
        nil)?.takeRetainedValue()
    else {
      return nil
    }
    let rect = self.frame(filter: filter, frame: frame, context: context)
    clipRect = rect
    cgContext.clip(to: rect)

    let transform = transform(filter: filter, frame: frame)
    cgContext.concatenate(transform)
    cgContext.setAlpha(opacity)
    cgContext.draw(image, in: effectRect)
    return cgContext.makeImage()
  }
}

extension SVGFeFloodElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
