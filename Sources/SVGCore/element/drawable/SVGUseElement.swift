import CoreGraphics
import Foundation

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
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  func contains(index: ObjectIdentifier) -> Bool {
    self.index == index || children.contains(where: { $0.index == index })
  }
}

extension SVGUseElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
