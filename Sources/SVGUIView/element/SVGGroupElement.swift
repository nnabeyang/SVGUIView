import UIKit

struct SVGGroupElement: SVGDrawableElement {
    var type: SVGElementName {
        .g
    }

    let base: SVGBaseElement

    let contentIds: [Int]
    let textAnchor: TextAnchor?

    private enum CodingKeys: String, CodingKey {
        case contentIds
    }

    init(attributes: [String: String], contentIds: [Int]) {
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
        textAnchor = other.textAnchor
    }

    init(other: SVGGroupElement, index _: Int, css _: SVGUIStyle) {
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
        let size = attributes["font-size"]
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

    func frame(context: SVGContext, path _: UIBezierPath?) -> CGRect {
        var rect: CGRect? = nil
        for index in contentIds {
            guard let content = context.contents[index] as? (any SVGDrawableElement) else { continue }
            if case .none = content.display ?? .inline {
                continue
            }
            if rect != nil {
                rect = CGRectUnion(rect!, content.frame(context: context, path: content.toBezierPath(context: context)).applying(content.transform ?? .identity))
            } else {
                rect = content.frame(context: context, path: content.toBezierPath(context: context)).applying(content.transform ?? .identity)
            }
        }
        return rect ?? .zero
    }

    func drawWithoutFilter(_ context: SVGContext, index _: Int, mode: DrawMode) async {
        context.saveGState()
        if mode != .filter(isRoot: true) {
            context.concatenate(transform ?? .identity)
        }
        context.setAlpha(opacity)
        let gContext = context.graphics
        gContext.beginTransparencyLayer(auxiliaryInfo: nil)
        font.map {
            context.push(font: $0)
        }
        writingMode.map {
            context.push(writingMode: $0)
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
        switch mode {
        case .root, .filter:
            context.pushClipIdStack()
            context.pushMaskIdStack()
        default:
            break
        }
        await clipPath?.clipIfNeeded(frame: frame(context: context, path: nil), context: context, cgContext: context.graphics)
        for index in contentIds {
            guard let content = context.contents[index] as? (any SVGDrawableElement) else { continue }
            await content.draw(context, index: index, mode: mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode)
        }
        switch mode {
        case .root, .filter:
            context.popClipIdStack()
            context.popMaskIdStack()
        default:
            break
        }
        font.map { _ in
            _ = context.popFont()
        }
        writingMode.map { _ in
            _ = context.popWritingMode()
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
        gContext.endTransparencyLayer()
        context.restoreGState()
    }

    func draw(_ context: SVGContext, index: Int, mode: DrawMode) async {
        guard !Task.isCancelled else { return }
        let filter = filter ?? SVGFilter.none
        if case let .url(id) = filter,
           let server = context.filters[id]
        {
            await server.filter(content: self, context: context, cgContext: context.graphics)
            return
        }
        await drawWithoutFilter(context, index: index, mode: mode)
    }

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

    func pattern(context: inout SVGBaseContext) {
        for index in contentIds {
            context.contents[index].pattern(context: &context)
        }
    }

    func filter(context: inout SVGBaseContext) {
        for index in contentIds {
            context.contents[index].filter(context: &context)
        }
    }

    func contains(index: Int, context _: SVGContext) -> Bool {
        contentIds.contains(index)
    }
}

extension SVGGroupElement {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(contentIds, forKey: .contentIds)
    }
}
