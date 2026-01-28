import Accelerate
import UIKit

final class SVGFilterElement: SVGDrawableElement {
  var base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let filterUnits: SVGUnitType?
  let primitiveUnits: SVGUnitType?

  let colorInterpolation: SVGColorInterpolation?
  let colorInterpolationFilters: SVGColorInterpolation?

  static var type: SVGElementName {
    .filter
  }

  var type: SVGElementName {
    .filter
  }

  var transform: CGAffineTransform {
    .identity
  }

  let children: [any SVGElement]

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    colorInterpolation = SVGColorInterpolation(rawValue: attributes["color-interpolation", default: ""])
    colorInterpolationFilters = SVGColorInterpolation(rawValue: attributes["color-interpolation-filters", default: ""])
    x = .init(attributes["x"])
    y = .init(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    filterUnits = SVGUnitType(rawValue: attributes["filterUnits", default: ""])
    primitiveUnits = SVGUnitType(rawValue: attributes["primitiveUnits", default: ""])
  }

  init(other: SVGFilterElement, css _: SVGUIStyle) {
    base = other.base
    colorInterpolation = other.colorInterpolation
    colorInterpolationFilters = other.colorInterpolationFilters
    x = other.x
    y = other.y
    width = other.width
    height = other.height
    filterUnits = other.filterUnits
    primitiveUnits = other.primitiveUnits
    children = other.children
  }

  private func colorSpace(colorInterpolation: SVGColorInterpolation) -> CGColorSpace {
    switch colorInterpolation {
    case .sRGB:
      return CGColorSpace(name: CGColorSpace.sRGB)!
    case .linearRGB:
      return CGColorSpace(name: CGColorSpace.linearSRGB)!
    }
  }

  func toBezierPath(context _: SVGContext) -> UIBezierPath? {
    nil
  }

  func filter(content: any SVGDrawableElement, context: SVGContext, cgContext: CGContext) async {
    guard !children.isEmpty else { return }
    let bezierPath = await content.toBezierPath(context: context)
    let frame = await content.frame(context: context, path: bezierPath)
    let effectRect = effectRect(frame: frame, context: context)
    guard let imageCgContext = await createImageCGContext(rect: effectRect, colorInterpolation: colorInterpolation ?? .sRGB),
      let srcImage = await srcImage(content: content, graphics: imageCgContext, rect: effectRect, context: context),
      let filterCgContext = await createImageCGContext(rect: effectRect, colorInterpolation: colorInterpolationFilters ?? .linearRGB)
    else { return }
    let scale = await UIScreen.main.scale
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -effectRect.minX, y: -effectRect.minY)
    filterCgContext.concatenate(transform)
    filterCgContext.saveGState()
    var results = [String: CGImage]()
    var inputImage = srcImage
    var clipRect = effectRect
    for (i, applier) in children.enumerated() {
      guard let applier = applier as? (any SVGFilterApplier) else { continue }
      filterCgContext.clear(effectRect)
      filterCgContext.restoreGState()
      filterCgContext.saveGState()
      guard
        let clippedImage = await applier.apply(
          srcImage: srcImage, inImage: inputImage, clipRect: &clipRect,
          filter: self, frame: frame, effectRect: effectRect, opacity: content.opacity,
          cgContext: filterCgContext, context: context, results: results, isFirst: i == 0)
      else { break }
      if let result = applier.result {
        results[result] = clippedImage
      }
      inputImage = clippedImage
    }
    cgContext.saveGState()
    cgContext.concatenate(content.transform ?? .identity)
    cgContext.draw(inputImage, in: effectRect)
    cgContext.restoreGState()
  }

  private func effectRect(frame: CGRect, context: SVGContext) -> CGRect {
    let filterUnits = filterUnits ?? .objectBoundingBox
    let x = x?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits, isPosition: true) ?? (frame.minX - 0.1 * frame.width)
    let y = y?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits, isPosition: true) ?? (frame.minY - 0.1 * frame.height)
    let width = width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits) ?? 1.2 * frame.width
    let height = height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits) ?? 1.2 * frame.height
    return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
  }

  private func createImageCGContext(rect: CGRect, colorInterpolation: SVGColorInterpolation) async -> CGContext? {
    let scale = await UIScreen.main.scale
    let frameWidth = Int((rect.width * scale).rounded(.up))
    let frameHeight = Int((rect.height * scale).rounded(.up))
    let bytesPerRow = 4 * frameWidth
    let cgContext = CGContext(
      data: nil,
      width: frameWidth,
      height: frameHeight,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace(colorInterpolation: colorInterpolation),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
    return cgContext
  }

  private func srcImage(content: any SVGDrawableElement, graphics: CGContext, rect: CGRect, context: SVGContext) async -> CGImage? {
    let nestContext = SVGContext(base: context.base, graphics: graphics, viewPort: context.viewPort)
    let scale = await UIScreen.main.scale
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -rect.minX, y: -rect.minY)
    graphics.concatenate(transform)

    nestContext.push(viewBox: context.viewBox)
    graphics.saveGState()
    guard !Task.isCancelled else { return nil }
    await content.drawWithoutFilter(nestContext, mode: .filter(isRoot: true))
    guard let image = graphics.makeImage() else { return nil }
    graphics.restoreGState()
    return image
  }

  func style(with _: Stylesheet) -> any SVGElement {
    Self(other: self, css: SVGUIStyle(decratations: [:]))
  }

  func filter(context: inout SVGBaseContext) {
    if let id = id, context.filters[id] == nil {
      context.setFilter(id: id, value: self)
    }
  }
}

extension SVGFilterElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}

extension CGImage {
  fileprivate static func fromvImageOutBuffer(_ outBuffer: vImage_Buffer) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue
    bitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue & CGBitmapInfo.alphaInfoMask.rawValue

    let context = CGContext(
      data: outBuffer.data,
      width: Int(outBuffer.width),
      height: Int(outBuffer.height),
      bitsPerComponent: 8,
      bytesPerRow: outBuffer.rowBytes,
      space: colorSpace,
      bitmapInfo: bitmapInfo)!

    return context.makeImage()
  }
}
