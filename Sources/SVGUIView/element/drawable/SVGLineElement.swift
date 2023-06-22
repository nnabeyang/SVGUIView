import UIKit

struct SVGLineElement: SVGDrawableElement {
    var type: SVGElementName {
        .line
    }

    let base: SVGBaseElement
    let x1: ElementLength?
    let y1: ElementLength?
    let x2: ElementLength?
    let y2: ElementLength?

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        x1 = .init(attributes["x1"])
        y1 = .init(attributes["y1"])
        x2 = .init(attributes["x2"])
        y2 = .init(attributes["y2"])
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        x1 = other.x1
        y1 = other.y1
        x2 = other.x2
        y2 = other.y2
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        let size = context.viewBox.size
        let x1 = x1?.value(total: size.width) ?? 0
        let y1 = y1?.value(total: size.height) ?? 0
        let x2 = x2?.value(total: size.width) ?? 0
        let y2 = y2?.value(total: size.height) ?? 0
        let start = CGPoint(x: x1, y: y1)
        let end = CGPoint(x: x2, y: y2)
        guard start != end else { return nil }
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

extension SVGLineElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case x1
        case y1
        case x2
        case y2
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(x1, forKey: .x1)
        try container.encode(y1, forKey: .y1)
        try container.encode(x1, forKey: .x2)
        try container.encode(y1, forKey: .y2)
        try container.encode(fill, forKey: .fill)
    }
}
