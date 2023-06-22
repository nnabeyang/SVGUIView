import UIKit

struct SVGEllipseElement: SVGDrawableElement {
    var type: SVGElementName {
        .ellipse
    }

    let base: SVGBaseElement
    let cx: ElementLength?
    let cy: ElementLength?
    let rx: ElementLength?
    let ry: ElementLength?

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        cx = ElementLength(attributes["cx"])
        cy = ElementLength(attributes["cy"])
        rx = ElementLength(attributes["rx"])
        ry = ElementLength(attributes["ry"])
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        cx = other.cx
        cy = other.cy
        rx = other.rx
        ry = other.ry
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        let size = context.viewBox.size
        let cx = cx?.value(total: size.width) ?? 0
        let cy = cy?.value(total: size.height) ?? 0
        let _rx = ((rx ?? ry)?.value(total: size.width)).flatMap { $0 < 0 ? nil : $0 }
        let _ry = ((ry ?? rx)?.value(total: size.height)).flatMap { $0 < 0 ? nil : $0 }
        let rx = _rx ?? _ry ?? 0
        let ry = _ry ?? _rx ?? 0
        guard rx > 0, ry > 0 else { return nil }
        return UIBezierPath(ovalIn: CGRect(origin: CGPoint(x: cx - rx, y: cy - ry), size: CGSize(width: 2 * rx, height: 2 * ry)))
    }
}

extension SVGEllipseElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case cx
        case cy
        case rx
        case ry
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(cx, forKey: .cx)
        try container.encode(cy, forKey: .cy)
        try container.encode(rx, forKey: .rx)
        try container.encode(ry, forKey: .ry)
        try container.encode(fill, forKey: .fill)
    }
}
