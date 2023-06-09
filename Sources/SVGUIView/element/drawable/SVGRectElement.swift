import UIKit

struct SVGRectElement: SVGDrawableElement {
    var type: SVGElementName {
        .rect
    }

    let base: SVGBaseElement
    let x: ElementLength
    let y: ElementLength
    let rx: ElementLength?
    let ry: ElementLength?
    let width: ElementLength
    let height: ElementLength

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        x = .init(attributes["x"]) ?? .pixel(0)
        y = .init(attributes["y"]) ?? .pixel(0)
        rx = .init(attributes["rx"])
        ry = .init(attributes["ry"])
        width = ElementLength(style: base.style[.width], value: attributes["width"]) ?? .pixel(0)
        height = ElementLength(style: base.style[.height], value: attributes["height"]) ?? .pixel(0)
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        x = other.x
        y = other.y
        rx = other.rx
        ry = other.ry
        width = ElementLength(style: css[.width], value: nil) ?? other.width
        height = ElementLength(style: css[.height], value: nil) ?? other.height
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        color.map {
            context.push(color: $0)
        }
        let size = context.viewBox.size
        let x = x.value(total: size.width)
        let y = y.value(total: size.height)
        let _rx = ((rx ?? ry)?.value(total: size.width)).flatMap { $0 < 0 ? nil : $0 }
        let _ry = ((ry ?? rx)?.value(total: size.height)).flatMap { $0 < 0 ? nil : $0 }
        let rx = _rx ?? _ry ?? 0
        let ry = _ry ?? _rx ?? 0
        let width = width.value(total: size.width)
        let height = height.value(total: size.height)
        if width == 0 || height == 0 {
            return nil
        }
        let cornerSize = CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry))
        return UIBezierPath(roundedRect: .init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
    }
}

extension SVGRectElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fill, forKey: .fill)
    }
}
