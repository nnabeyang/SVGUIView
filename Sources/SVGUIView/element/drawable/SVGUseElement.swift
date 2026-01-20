import UIKit

final class SVGUseElement: SVGDrawableElement {
  static var type: SVGElementName {
    .use
  }

  var type: SVGElementName {
    .use
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let parentId: String?
  let attributes: [String: String]
  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    parentId = Self.parseLink(description: attributes["href"])
    self.attributes = attributes
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(other: SVGUseElement, attributes: [String: String]) {
    base = SVGBaseElement(other: other.base, attributes: attributes)
    x = other.x
    y = other.y
    width = other.width
    height = other.height
    parentId = other.parentId
    self.attributes = other.attributes
    children = other.children
  }

  init(other: SVGUseElement, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, css: css)
    x = other.x
    y = other.y
    width = other.width
    height = other.height
    parentId = other.parentId
    attributes = other.attributes
    children = other.children
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  func style(with _: Stylesheet) -> any SVGElement {
    Self(other: self, css: SVGUIStyle(decratations: [:]))
  }

  private func getParent(context: SVGContext, index: ObjectIdentifier) -> (any SVGDrawableElement)? {
    _ = context.check(tagId: index)
    guard let parentId = parentId,
      let element = context[parentId],
      context.check(tagId: element.index),
      !element.contains(index: index, context: context)
    else {
      return nil
    }
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    let transform = CGAffineTransform(translationX: x, y: y)
    context.concatenate(transform)
    let parentElement = element.use(attributes: attributes)
    return parentElement
  }

  func toBezierPath(context: SVGContext) async -> UIBezierPath? {
    guard let element = getParent(context: context, index: index)
    else {
      return nil
    }
    return await element.toBezierPath(context: context)
  }

  func draw(_ context: SVGContext, mode: DrawMode) async {
    guard !Task.isCancelled else { return }
    let gContext = context.graphics
    gContext.saveGState()
    defer {
      gContext.restoreGState()
    }
    switch mode {
    case .root, .filter:
      context.pushTagIdStack()
      context.pushClipIdStack()
      context.pushMaskIdStack()
      context.pushPatternIdStack()
    default:
      break
    }
    guard let newElement = getParent(context: context, index: index) else { return }
    await newElement.draw(context, mode: .normal)
    switch mode {
    case .root, .filter:
      context.popTagIdStack()
      context.popClipIdStack()
      context.popMaskIdStack()
      context.popPatternIdStack()
    default:
      break
    }
  }

  func contains(index: ObjectIdentifier, context _: SVGContext) -> Bool {
    self.index == index || children.contains(where: { $0.index == index })
  }
}

extension SVGUseElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
