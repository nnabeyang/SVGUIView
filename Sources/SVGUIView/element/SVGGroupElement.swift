import UIKit

final class SVGGroupElement: SVGDrawableElement {
  static var type: SVGElementName {
    .g
  }

  var type: SVGElementName {
    .g
  }

  let base: SVGBaseElement

  let children: [any SVGElement]
  let textAnchor: TextAnchor?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    textAnchor = TextAnchor(rawValue: base.attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(other: SVGGroupElement, attributes: [String: String]) {
    base = SVGBaseElement(other: other.base, attributes: attributes)
    children = other.children
    textAnchor = other.textAnchor
  }

  init(other: SVGGroupElement, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, css: css)
    children = other.children
    textAnchor = other.textAnchor
  }

  func toBezierPath(context _: SVGContext) -> UIBezierPath? {
    nil
  }

  private static func parseFont(attributes: [String: String]) -> SVGUIFont? {
    let name = attributes["font-family"]?.trimmingCharacters(in: .whitespaces)
    let size = attributes["font-size"]
    let weight = attributes["font-weight"]?.trimmingCharacters(in: .whitespaces)
    if name == nil,
      size == nil,
      weight == nil
    {
      return nil
    }
    return SVGUIFont(name: name, size: size, weight: weight)
  }

  func frame(context: SVGContext, path _: UIBezierPath?) async -> CGRect {
    var rect: CGRect? = nil
    for content in children {
      guard let content = content as? (any SVGDrawableElement) else { continue }
      if case .none = content.display ?? .inline {
        continue
      }
      if rect != nil {
        rect = await CGRectUnion(rect!, content.frame(context: context, path: content.toBezierPath(context: context)).applying(content.transform ?? .identity))
      } else {
        rect = await content.frame(context: context, path: content.toBezierPath(context: context)).applying(content.transform ?? .identity)
      }
    }
    return rect ?? .zero
  }

  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async {
    context.saveGState()
    if mode != .filter(isRoot: true) {
      context.concatenate(transform ?? .identity)
    }
    context.setAlpha(opacity)
    let gContext = context.graphics
    gContext.beginTransparencyLayer(auxiliaryInfo: nil)
    font.map {
      context.push(font: $0)
    }
    writingMode.map {
      context.push(writingMode: $0)
    }
    fill.map {
      context.push(fill: $0)
    }
    color.map {
      context.push(color: $0)
    }
    context.push(stroke: stroke)
    textAnchor.map {
      context.push(textAnchor: $0)
    }
    switch mode {
    case .root, .filter:
      context.pushClipIdStack()
      context.pushMaskIdStack()
    default:
      break
    }
    await clipPath?.clipIfNeeded(frame: frame(context: context, path: nil), context: context, cgContext: context.graphics)
    for content in children {
      guard let content = content as? (any SVGDrawableElement) else { continue }
      await content.draw(context, mode: mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode)
    }
    switch mode {
    case .root, .filter:
      context.popClipIdStack()
      context.popMaskIdStack()
    default:
      break
    }
    font.map { _ in
      _ = context.popFont()
    }
    writingMode.map { _ in
      _ = context.popWritingMode()
    }
    fill.map { _ in
      _ = context.popFill()
    }
    color.map { _ in
      _ = context.popColor()
    }
    _ = context.popStroke()
    textAnchor.map { _ in
      _ = context.popTextAnchor()
    }
    gContext.endTransparencyLayer()
    context.restoreGState()
  }

  func draw(_ context: SVGContext, mode: DrawMode) async {
    guard !Task.isCancelled else { return }
    let filter = filter ?? SVGFilter.none
    if case .url(let id) = filter,
      let server = context.filters[id]
    {
      await server.filter(content: self, context: context, cgContext: context.graphics)
      return
    }
    await drawWithoutFilter(context, mode: mode)
  }

  func clip(context: inout SVGBaseContext) {
    clipRule.map {
      context.push(clipRule: $0)
    }
    for child in children {
      child.clip(context: &context)
    }
    clipRule.map { _ in
      _ = context.popClipRule()
    }
  }

  func mask(context: inout SVGBaseContext) {
    for child in children {
      child.mask(context: &context)
    }
  }

  func pattern(context: inout SVGBaseContext) {
    for child in children {
      child.pattern(context: &context)
    }
  }

  func filter(context: inout SVGBaseContext) {
    for child in children {
      child.filter(context: &context)
    }
  }

  func contains(index: ObjectIdentifier, context _: SVGContext) -> Bool {
    children.contains(where: { $0.index == index })
  }
}

extension SVGGroupElement {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
