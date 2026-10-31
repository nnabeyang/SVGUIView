import Foundation

/// An element that SVGUIView doesn't know, or that isn't in the SVG namespace, such as `<title>` or the content of
/// `<foreignObject>`. It isn't rendered, and neither are its descendants, but other elements can reference them, as
/// a `<use>` element that shows an element in it does.
final class SVGUnknownElement: SVGElement {
  static var type: SVGElementName {
    .unknown
  }

  var type: SVGElementName {
    .unknown
  }

  let base: SVGBaseElement

  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
  }

  func clip(context: inout SVGBaseContext) {
    for child in children {
      child.clip(context: &context)
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

  func contains(index: ObjectIdentifier) -> Bool {
    children.contains(where: { $0.index == index })
  }
}

extension SVGUnknownElement {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
