final class SVGFeMergeNodeElement: SVGElement {
  static var type: SVGElementName {
    .feMergeNode
  }

  var type: SVGElementName {
    .feMergeNode
  }

  let base: SVGBaseElement
  let input: SVGFilterInput?

  func style(with _: Stylesheet) -> any SVGElement {
    self
  }

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    let attributes = base.attributes
    self.base = base
    input = SVGFilterInput(rawValue: attributes["in", default: ""])
  }
}

extension SVGFeMergeNodeElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
