import Accelerate
import UIKit

enum SVGBlendMode: String {
  case normal
  case multiply
  case screen
  case overlay
  case darken
  case lighten
  case colorDodge = "color-dodge"
  case colorBurn = "color-burn"
  case hardLight = "hard-light"
  case softLight = "soft-light"
  case difference
  case exclusion
  case saturation
  case color
  case luminosity
  case hue

  var toCgBlendMode: CGBlendMode {
    switch self {
    case .normal:
      return .normal
    case .multiply:
      return .multiply
    case .screen:
      return .screen
    case .overlay:
      return .overlay
    case .darken:
      return .darken
    case .lighten:
      return .lighten
    case .colorDodge:
      return .colorDodge
    case .colorBurn:
      return .colorBurn
    case .hardLight:
      return .hardLight
    case .softLight:
      return .softLight
    case .difference:
      return .difference
    case .exclusion:
      return .exclusion
    case .saturation:
      return .saturation
    case .color:
      return .color
    case .luminosity:
      return .luminosity
    case .hue:
      return .hue
    }
  }
}

struct SVGFeBlendElement: SVGElement, SVGFilterApplier {
  private static let maxKernelSize: UInt32 = 100
  var type: SVGElementName {
    .feBlend
  }

  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let mode: SVGBlendMode?
  let input: SVGFilterInput?
  let input2: SVGFilterInput?

  func style(with _: CSSStyle, at _: Int) -> any SVGElement {
    self
  }

  init(attributes: [String: String]) {
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    mode = SVGBlendMode(rawValue: attributes["mode", default: ""])
    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    input2 = SVGFilterInput(rawValue: attributes["in2", default: ""])
  }

  func apply(
    srcImage: CGImage, inImage: CGImage, clipRect: inout CGRect,
    filter: SVGFilterElement, frame: CGRect, effectRect: CGRect, opacity: CGFloat, cgContext: CGContext, context: SVGContext, results: [String: CGImage], isFirst _: Bool
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format),
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format),
      let image1 = inputImage(
        input: input, format: &format,
        results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer),
      let image2 = inputImage(
        input: input2, format: &format,
        results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
    else { return nil }
    let rect = self.frame(filter: filter, frame: frame, context: context)
    let transform = transform(filter: filter, frame: frame)
    cgContext.concatenate(transform)
    cgContext.setAlpha(opacity)
    cgContext.draw(image2, in: rect)
    let mode = mode ?? .normal
    cgContext.setBlendMode(mode.toCgBlendMode)
    cgContext.draw(image1, in: effectRect)

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

extension SVGFeBlendElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
