import UIKit

struct SVGDefsElement: SVGDrawableElement {
    var type: SVGElementName {
        .defs
    }

    let base: SVGBaseElement

    let contentIds: [Int]

    private enum CodingKeys: String, CodingKey {
        case contentIds
    }

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)
        self.contentIds = contentIds
    }

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(other: Self, attributes: [String: String]) {
        base = SVGBaseElement(other: other.base, attributes: attributes)
        contentIds = other.contentIds
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        contentIds = other.contentIds
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

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    func draw(_: SVGContext, index _: Int, depth _: Int, isRoot _: Bool) {}

    func clip(context: inout SVGBaseContext) {
        clipRule.map {
            context.push(clipRule: $0)
        }
        for index in contentIds {
            context.contents[index].clip(context: &context)
        }
        clipRule.map { _ in
            _ = context.popClipRule()
        }
    }

    func mask(context: inout SVGBaseContext) {
        for index in contentIds {
            context.contents[index].mask(context: &context)
        }
    }

    func contains(index: Int, context _: SVGContext) -> Bool {
        contentIds.contains(index)
    }
}

extension SVGDefsElement {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(contentIds, forKey: .contentIds)
    }
}
