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
    let x: ElementLength?
    let y: ElementLength?

    init(base: SVGBaseElement, text: String, attributes: [String: String]) {
        self.base = base
        self.text = text
        font = Self.parseFont(attributes: attributes)
        textAnchor = TextAnchor(rawValue: attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
        x = .init(attributes["x"])
        y = .init(attributes["y"])
    }

    private static func parseFont(attributes: [String: String]) -> SVGUIFont {
        let name = attributes["font-family"]
        let size = Double(attributes["font-size", default: ""]).flatMap { CGFloat($0) }
        let weight = attributes["font-weight"]
        return SVGUIFont(name: name, size: size, weight: weight)
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        text = other.text
        font = other.font
        textAnchor = other.textAnchor
        x = other.x
        y = other.y
    }

    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext) {
        guard let fill = fill else {
            path.fill()
            return
        }
        switch fill {
        case .inherit:
            if let fill = context.fill {
                applySVGFill(fill: fill, path: path, context: context)
            }
        case .current:
            if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
                uiColor.setFill()
                path.fill()
            }
        case let .color(color, opacity):
            let opacity = opacity ?? 1.0
            if let uiColor = color?.toUIColor(opacity: self.opacity * opacity) {
                uiColor.setFill()
                path.fill()
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

    func frame(context: SVGContext) -> CGRect {
        guard let line = getLine(context: context) else { return .zero }
        return CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        let size = context.viewBox.size
        let x = x?.value(total: size.width) ?? 0
        let y = y?.value(total: size.height) ?? 0
        let transform = CGAffineTransform(translationX: x, y: y)
        context.concatenate(transform)
        guard let line = getLine(context: context) else { return nil }
        let gContext = context.graphics
        gContext.scaleBy(x: 1.0, y: -1.0)
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
        let rect = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
        if case .middle = textAnchor ?? context.textAnchor ?? .start {
            gContext.translateBy(x: -rect.width / 2.0, y: 0)
        }
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
