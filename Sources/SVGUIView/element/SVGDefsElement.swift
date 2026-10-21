import CoreGraphics
import Foundation

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

  func toPath(context _: SVGContext) -> CGPath? {
    nil
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

extension SVGDefsElement {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
