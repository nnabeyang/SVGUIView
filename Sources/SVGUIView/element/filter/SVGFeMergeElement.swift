import Accelerate
import UIKit

final class SVGFeMergeElement: SVGElement, SVGFilterApplier {
  let base: SVGBaseElement
  var x: SVGLength?
  var y: SVGLength?
  var width: SVGLength?
  var height: SVGLength?

  var result: String?
  let colorInterpolationFilters: SVGColorInterpolation?

  static var type: SVGElementName {
    .feMergeNode
  }

  var type: SVGElementName {
    .feMergeNode
  }

  let children: [any SVGElement]

  func style(with _: Stylesheet) -> any SVGElement {
    self
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]
    colorInterpolationFilters = SVGColorInterpolation(rawValue: attributes["color-interpolation-filters", default: ""])
  }

  private func colorSpace(colorInterpolation: SVGColorInterpolation) -> CGColorSpace {
    switch colorInterpolation {
    case .sRGB:
      return CGColorSpace(name: CGColorSpace.sRGB)!
    case .linearRGB:
      return CGColorSpace(name: CGColorSpace.linearSRGB)!
    }
  }

  func apply(srcImage: CGImage, inImage: CGImage, clipRect: inout CGRect, filter: SVGFilterElement, frame: CGRect, effectRect _: CGRect, opacity: CGFloat, cgContext: CGContext, context: SVGContext, results: [String: CGImage], isFirst: Bool) -> CGImage? {
    let colorSpace = colorInterpolationFilters.map { self.colorSpace(colorInterpolation: $0) } ?? (isFirst ? srcImage.colorSpace! : inImage.colorSpace!)
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: colorSpace,
        bitmapInfo: srcImage.bitmapInfo),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format),
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format)
    else { return nil }
    let rect = self.frame(filter: filter, frame: frame, context: context)
    let transform = transform(filter: filter, frame: frame)
    cgContext.concatenate(transform)
    cgContext.setAlpha(opacity)

    for node in children {
      guard let node = node as? SVGFeMergeNodeElement else { continue }
      guard
        let image = inputImage(
          input: node.input, format: &format,
          results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
      else { return nil }
      cgContext.draw(image, in: rect)
    }
    clipRect = rect
    cgContext.clip(to: rect)
    return cgContext.makeImage()
  }

  private func inputImage(
    input: SVGFilterInput?, format: inout vImage_CGImageFormat, results: [String: CGImage],
    srcBuffer: inout vImage_Buffer, inputBuffer: inout vImage_Buffer
  ) -> CGImage? {
    let data = malloc(inputBuffer.rowBytes * Int(inputBuffer.height))
    defer {
      free(data)
    }
    var destBuffer = vImage_Buffer(data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
    inputImageBuffer(input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer, destBuffer: &destBuffer)

    return vImageCreateCGImageFromBuffer(
      &destBuffer,
      &format,
      { _, _ in },
      nil,
      vImage_Flags(kvImageNoAllocate),
      nil)?.takeRetainedValue()
  }
}

extension SVGFeMergeElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
