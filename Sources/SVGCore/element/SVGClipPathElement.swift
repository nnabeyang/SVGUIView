import CoreGraphics
import Foundation

final class SVGClipPathElement: SVGElement {
  static var type: SVGElementName {
    .clipPath
  }

  var type: SVGElementName {
    .clipPath
  }

  let base: SVGBaseElement
  let children: [any SVGElement]
  let clipPathUnits: SVGUnitType?
  let clipPath: SVGClipPath?
  let id: String?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children

    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    clipPathUnits = SVGUnitType(rawValue: attributes["clipPathUnits", default: ""])
    clipPath = base.style.clipPath
  }

  func clip(context: inout SVGBaseContext) {
    if let id = id, context.clipPaths[id] == nil {
      context.setClipPath(id: id, value: self)
    }
  }
}

extension SVGClipPathElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
