import Foundation

struct SVGGroupElement: SVGElement {
    var type: SVGElementName {
        .g
    }

    let transform: CGAffineTransform
    let contents: [SVGElement]
    let font: SVGUIFont?
    let opacity: Double
    let fill: SVGFill?
    let color: SVGUIColor?
    let stroke: SVGUIStroke?
    let textAnchor: TextAnchor?
    let style: SVGUIStyle

    private enum CodingKeys: String, CodingKey {
        case contents
    }

    init(attributes: [String: String], contents: [SVGElement]) {
        transform = CGAffineTransform(description: attributes["transform", default: ""])
        self.contents = contents
        font = Self.parseFont(attributes: attributes)
        style = SVGUIStyle(description: attributes["style", default: ""])
        fill = SVGFill(style: style, attributes: attributes)
        color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        stroke = SVGUIStroke(attributes: attributes)
        opacity = Double(attributes["opacity", default: "1"]) ?? 1.0
        textAnchor = TextAnchor(rawValue: attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
    }

    private static func parseFont(attributes: [String: String]) -> SVGUIFont? {
        let name = attributes["font-family"]?.trimmingCharacters(in: .whitespaces)
        let size = Double(attributes["font-size", default: ""]).flatMap { CGFloat($0) }
        let weight = attributes["font-weight"]?.trimmingCharacters(in: .whitespaces)
        if name == nil,
           size == nil,
           weight == nil
        {
            return nil
        }
        return SVGUIFont(name: name, size: size, weight: weight)
    }

    func style(with _: CSSStyle) -> any SVGElement {
        self
    }

    func draw(_ context: SVGContext) {
        context.saveGState()
        context.concatenate(transform)
        let gcontext = context.graphics
        context.setAlpha(opacity)
        gcontext.beginTransparencyLayer(auxiliaryInfo: nil)
        font.map {
            context.push(font: $0)
        }
        fill.map {
            context.push(fill: $0)
        }
        color.map {
            context.push(color: $0)
        }
        stroke.map {
            context.push(stroke: $0)
        }
        textAnchor.map {
            context.push(textAnchor: $0)
        }
        for node in contents {
            node.draw(context)
        }
        font.map { _ in
            _ = context.popFont()
        }
        fill.map { _ in
            _ = context.popFill()
        }
        color.map { _ in
            _ = context.popColor()
        }
        stroke.map { _ in
            _ = context.popStroke()
        }
        textAnchor.map { _ in
            _ = context.popTextAnchor()
        }
        gcontext.endTransparencyLayer()
        context.restoreGState()
    }
}

extension SVGGroupElement {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        var contentsContainer = container.nestedUnkeyedContainer(forKey: .contents)
        for content in contents {
            try contentsContainer.encode(content)
        }
    }
}

extension CGAffineTransform {
    init(style: CSSValue?, description: String) {
        if case let .transform(value) = style {
            self = value
            return
        }
        self = .init(description: description)
    }

    init(description: String) {
        var data = description
        let ops = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var parser = SVGAttributeScanner(bytes: bytes)
            return parser.scanTransform()
        }
        var transform: CGAffineTransform = .identity
        for op in ops {
            op.apply(transform: &transform)
        }
        self = transform
    }
}
