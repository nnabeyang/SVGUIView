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
  /// The ID of the element of the document that the element shows, or `nil` if it shows none, or one of another
  /// document.
  let parentId: String?
  /// The URL of another document and the ID of its element that the element shows, or `nil` if it shows an element
  /// of its document, or none. A data URL isn't another document.
  let externalHref: (url: String, id: String)?
  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    // `x` and `y` are geometry properties, which style sheets set, and whose presentation attributes are read as CSS.
    // `width` and `height` are attributes, which take math functions as the lengths of SVG 2 do.
    x = base.style.x
    y = base.style.y
    width = attributes["width"].flatMap { SVGLength(property: $0, isNonNegative: true) }
    height = attributes["height"].flatMap { SVGLength(property: $0, isNonNegative: true) }
    parentId = fragmentID(of: attributes["href"])
    externalHref = Self.externalHref(attributes["href"])
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  /// The URL and the ID of an `href` that names an element of another document, such as `other.svg#a`.
  static func externalHref(_ href: String?) -> (url: String, id: String)? {
    guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.hasPrefix("#"),
      !href.lowercased().hasPrefix("data:"), let hash = href.firstIndex(of: "#")
    else { return nil }
    let url = String(href[..<hash])
    let id = String(href[href.index(after: hash)...])
    guard !url.isEmpty, !id.isEmpty else { return nil }
    return (url, id.removingPercentEncoding ?? id)
  }

  func contains(index: ObjectIdentifier) -> Bool {
    self.index == index || children.contains(where: { $0.index == index })
  }
}
