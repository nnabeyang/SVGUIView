import UIKit

enum TextAnchor: String {
    case start
    case middle
    case end
}

struct SVGTextElement: SVGDrawableElement {
    var type: SVGElementName {
        .text
    }

    let base: SVGBaseElement
    let text: String
    let font: SVGUIFont
    let textAnchor: TextAnchor?
    let x: SVGLength?
    let y: SVGLength?

    init(base: SVGBaseElement, text: String, attributes: [String: String]) {
        self.base = base
        self.text = text
        font = Self.parseFont(attributes: attributes)
        textAnchor = TextAnchor(rawValue: attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
        x = SVGLength(attributes["x"])
        y = SVGLength(attributes["y"])
    }

    init(other: Self, attributes: [String: String]) {
        base = SVGBaseElement(other: other.base, attributes: attributes)
        text = other.text
        font = SVGUIFont(lhs: other.font, rhs: Self.parseFont(attributes: attributes))
        textAnchor = other.textAnchor ?? TextAnchor(rawValue: attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
        x = other.x
        y = other.y
    }

    private static func parseFont(attributes: [String: String]) -> SVGUIFont {
        let name = attributes["font-family"]
        let size = Double(attributes["font-size", default: ""]).flatMap { CGFloat($0) }
        let weight = attributes["font-weight"]
        return SVGUIFont(name: name, size: size, weight: weight)
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        text = other.text
        font = other.font
        textAnchor = other.textAnchor
        x = other.x
        y = other.y
    }

    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext, isRoot: Bool) {
        let cgContext = context.graphics
        guard let fill = fill else {
            cgContext.addPath(path.cgPath)
            cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            return
        }
        switch fill {
        case .inherit:
            if let fill = context.fill {
                applySVGFill(fill: fill, path: path, context: context, isRoot: isRoot)
            }
        case .current:
            if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
                cgContext.setFillColor(uiColor.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            }
        case let .color(color, opacity):
            let opacity = opacity ?? 1.0
            if let uiColor = color?.toUIColor(opacity: self.opacity * opacity) {
                cgContext.setFillColor(uiColor.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            }
        case .url:
            fatalError()
        }
    }

    private func getLine(context: SVGContext) -> CTLine? {
        var attributes: [CFString: Any] = [:]
        let ctFont: CTFont = {
            if let contextFont = context.font {
                return SVGUIFont(lhs: font, rhs: contextFont).toCTFont
            }
            return font.toCTFont
        }()
        attributes[kCTFontAttributeName] = ctFont

        guard let attributedText = CFAttributedStringCreate(kCFAllocatorDefault,
                                                            text as NSString,
                                                            attributes as CFDictionary) else { return nil }
        return CTLineCreateWithAttributedString(attributedText)
    }

    func frame(context: SVGContext, path _: UIBezierPath) -> CGRect {
        guard let line = getLine(context: context) else { return .zero }
        let x = x?.value(context: context, mode: .width) ?? 0
        let y = y?.value(context: context, mode: .height) ?? 0
        var transform = CGAffineTransform(translationX: x, y: y)
            .scaledBy(x: 1.0, y: -1.0)
        let rect = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
        if case .middle = textAnchor ?? context.textAnchor ?? .start {
            transform = transform.translatedBy(x: -rect.width / 2.0, y: 0)
        }
        return rect.applying(transform)
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        guard let line = getLine(context: context) else { return nil }
        let letters = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line)
        for i in 0 ..< CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
            let fontPointer = CFDictionaryGetValue(CTRunGetAttributes(run), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
            let runFont = unsafeBitCast(fontPointer, to: CTFont.self)

            for index in 0 ..< CTRunGetGlyphCount(run) {
                let range = CFRange(location: index, length: 1)
                var glyph = CGGlyph()
                var position = CGPoint()
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)

                guard let letter = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                letters.addPath(letter, transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }

        let path = UIBezierPath(cgPath: letters)
        let x = x?.value(context: context, mode: .width) ?? 0
        let y = y?.value(context: context, mode: .height) ?? 0
        var transform = CGAffineTransform(translationX: x, y: y)
            .scaledBy(x: 1.0, y: -1.0)

        let rect = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
        if case .middle = textAnchor ?? context.textAnchor ?? .start {
            transform = transform.translatedBy(x: -rect.width / 2.0, y: 0)
        }
        path.apply(transform)
        return path
    }
}

extension SVGTextElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case text
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(text, forKey: .text)
        if let fill = fill {
            try container.encode(fill, forKey: .fill)
        }
    }
}
