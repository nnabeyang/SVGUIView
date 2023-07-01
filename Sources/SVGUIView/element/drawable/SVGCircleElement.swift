import UIKit

struct SVGCircleElement: SVGDrawableElement {
    var type: SVGElementName {
        .circle
    }

    let base: SVGBaseElement
    let cx: ElementLength?
    let cy: ElementLength?
    let r: ElementLength?

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        cx = .init(attributes["cx"])
        cy = .init(attributes["cy"])
        r = .init(attributes["r"])
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        cx = other.cx
        cy = other.cy
        r = other.r
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        let size = context.viewBox.size
        let cx = cx?.value(total: size.width) ?? 0
        let cy = cy?.value(total: size.height) ?? 0
        let r = r?.value(total: sqrt(size.width * size.width + size.height * size.height) / sqrt(2.0)) ?? 0
        guard r > 0 else { return nil }
        return UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: true)
    }
}

extension SVGCircleElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case cx
        case cy
        case r
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(cx, forKey: .cx)
        try container.encode(cy, forKey: .cy)
        try container.encode(r, forKey: .r)
        try container.encode(fill, forKey: .fill)
    }
}
