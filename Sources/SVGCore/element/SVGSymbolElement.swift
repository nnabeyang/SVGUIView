import CoreGraphics
import Foundation

/// A `<symbol>`, which isn't rendered itself: a `<use>` element that references it shows its children in a viewport
/// of its own, as an `<svg>` element shows them.
final class SVGSymbolElement: SVGDrawableElement {
  static var type: SVGElementName {
    .symbol
  }

  var type: SVGElementName {
    .symbol
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

extension SVGSymbolElement {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
