import UIKit

final class SVGDefsElement: SVGDrawableElement {
  static var type: SVGElementName {
    .defs
  }

  var type: SVGElementName {
    .defs
  }

  let base: SVGBaseElement

  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(other: SVGDefsElement, attributes: [String: String]) {
    base = SVGBaseElement(other: other.base, attributes: attributes)
    children = other.children
  }

  init(other: SVGDefsElement, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, css: css)
    children = other.children
  }

  func toBezierPath(context _: SVGContext) -> UIBezierPath? {
    nil
  }

  func style(with _: Stylesheet) -> any SVGElement {
    Self(other: self, css: SVGUIStyle(decratations: [:]))
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

extension SVGDefsElement {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
