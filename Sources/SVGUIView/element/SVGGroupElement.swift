import UIKit

struct SVGGroupElement: SVGDrawableElement {
    var type: SVGElementName {
        .g
    }

    let base: SVGBaseElement

    let contentIds: [Int]
    let font: SVGUIFont?
    let textAnchor: TextAnchor?

    private enum CodingKeys: String, CodingKey {
        case contentIds
    }

    init(attributes: [String: String], contentIds: [Int]) {
        font = Self.parseFont(attributes: attributes)
        base = SVGBaseElement(attributes: attributes)
        self.contentIds = contentIds
        textAnchor = TextAnchor(rawValue: attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
    }

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(other: Self, attributes: [String: String]) {
        base = SVGBaseElement(other: other.base, attributes: attributes)
        contentIds = other.contentIds
        font = other.font
        textAnchor = other.textAnchor
    }

    init(other: SVGGroupElement, css _: SVGUIStyle) {
        self = other
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        nil
    }

    private static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanColor()
        }
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

    func draw(_ context: SVGContext, index _: Int, depth: Int) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
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
        context.push(stroke: stroke)
        textAnchor.map {
            context.push(textAnchor: $0)
        }
        for index in contentIds {
            context.contents[index].draw(context, index: index, depth: depth + 1)
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
        _ = context.popStroke()
        textAnchor.map { _ in
            _ = context.popTextAnchor()
        }
        gcontext.endTransparencyLayer()
        context.restoreGState()
    }

    func contains(index: Int, context _: SVGContext) -> Bool {
        contentIds.contains(index)
    }
}

extension SVGGroupElement {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(contentIds, forKey: .contentIds)
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
