struct SVGFeMergeNodeElement: SVGElement {
  var type: SVGElementName {
    .feMergeNode
  }

  let input: SVGFilterInput?

  func style(with _: CSSStyle, at _: Int) -> any SVGElement {
    self
  }

  init(attributes: [String: String]) {
    input = SVGFilterInput(rawValue: attributes["in", default: ""])
  }
}

extension SVGFeMergeNodeElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
