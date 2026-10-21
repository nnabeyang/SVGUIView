import CoreGraphics
import Foundation

final class SVGFilterElement: SVGDrawableElement {
  let base: SVGBaseElement
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
    colorInterpolation = base.style.colorInterpolation
    colorInterpolationFilters = base.style.colorInterpolationFilters
    x = .init(attributes["x"])
    y = .init(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    filterUnits = SVGUnitType(rawValue: attributes["filterUnits", default: ""])
    primitiveUnits = SVGUnitType(rawValue: attributes["primitiveUnits", default: ""])
  }

  private func colorSpace(colorInterpolation: SVGColorInterpolation) -> CGColorSpace {
    switch colorInterpolation {
    case .sRGB:
      return CGColorSpace(name: CGColorSpace.sRGB)!
    case .linearRGB:
      return CGColorSpace(name: CGColorSpace.linearSRGB)!
    }
  }

  func toPath(context _: SVGContext) -> CGPath? {
    nil
  }

  /// Applies the filter to an element.
  ///
  /// - Parameters:
  ///   - content: The element, whose bounds the filter region is relative to.
  ///   - context: The context of the parent of the element.
  ///   - cgContext: The context to draw the filtered element into.
  ///   - paintSource: Paints the element without its filter into a context, which is the source image.
  func filter(
    content: any SVGDrawableElement, context: SVGContext, cgContext: CGContext,
    paintSource: (CGContext) async -> Void
  ) async {
    guard !children.isEmpty else { return }
    let contentContext = context.styled(by: content)
    let path = await content.toPath(context: contentContext)
    let frame = await content.frame(context: contentContext, path: path)
    let effectRect = effectRect(frame: frame, context: context)
    guard let imageCgContext = createImageCGContext(rect: effectRect, scale: context.scale, colorInterpolation: colorInterpolation ?? .sRGB),
      let srcImage = await srcImage(graphics: imageCgContext, rect: effectRect, context: context, paint: paintSource),
      let filterCgContext = createImageCGContext(rect: effectRect, scale: context.scale, colorInterpolation: colorInterpolationFilters ?? .linearRGB)
    else { return }
    let scale = context.scale
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -effectRect.minX, y: -effectRect.minY)
    filterCgContext.concatenate(transform)
    filterCgContext.saveGState()
    var results = [String: CGImage]()
    var inputImage = srcImage
    var clipRect = effectRect
    for (i, applier) in children.enumerated() {
      // Leave the loop rather than return, so that the graphics states stay balanced. A cancelled rendering
      // throws its image away.
      if Task.isCancelled { break }
      await Task.yield()
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

  private func createImageCGContext(rect: CGRect, scale: CGFloat, colorInterpolation: SVGColorInterpolation) -> CGContext? {
    CGContext.bitmap(size: rect.size, scale: scale, space: colorSpace(colorInterpolation: colorInterpolation))
  }

  private func srcImage(
    graphics: CGContext, rect: CGRect, context: SVGContext, paint: (CGContext) async -> Void
  ) async -> CGImage? {
    let scale = context.scale
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -rect.minX, y: -rect.minY)
    graphics.concatenate(transform)

    graphics.saveGState()
    guard !Task.isCancelled else { return nil }
    await paint(graphics)
    guard let image = graphics.makeImage() else { return nil }
    graphics.restoreGState()
    return image
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
