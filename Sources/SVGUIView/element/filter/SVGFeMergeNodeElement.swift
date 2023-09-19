struct SVGFeMergeNodeElement: SVGElement {
    var type: SVGElementName {
        .feMergeNode
    }

    let input: SVGFilterInput?

    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {
        fatalError()
    }

    func style(with _: CSSStyle, at _: Int) -> SVGElement {
        self
    }

    init(attributes: [String: String]) {
        input = SVGFilterInput(rawValue: attributes["in", default: ""])
    }

    func drawWithoutFilter(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {
        fatalError()
    }
}

extension SVGFeMergeNodeElement: Encodable {
    func encode(to _: Encoder) throws {
        fatalError()
    }
}
