import UIKit

struct SVGLineElement: SVGDrawableElement {
    var type: SVGElementName {
        .line
    }

    let base: SVGBaseElement
    let x1: SVGLength?
    let y1: SVGLength?
    let x2: SVGLength?
    let y2: SVGLength?

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        x1 = .init(attributes["x1"])
        y1 = .init(attributes["y1"])
        x2 = .init(attributes["x2"])
        y2 = .init(attributes["y2"])
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        x1 = other.x1
        y1 = other.y1
        x2 = other.x2
        y2 = other.y2
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        let x1 = x1?.value(context: context, mode: .width) ?? 0
        let y1 = y1?.value(context: context, mode: .height) ?? 0
        let x2 = x2?.value(context: context, mode: .width) ?? 0
        let y2 = y2?.value(context: context, mode: .height) ?? 0
        let start = CGPoint(x: x1, y: y1)
        let end = CGPoint(x: x2, y: y2)
        guard start != end else { return nil }
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    func frame(context: SVGContext, path: UIBezierPath?) -> CGRect {
        guard let path = path else { return .zero }
        let r = path.cgPath.boundingBoxOfPath
        if r.width > 0, r.height > 0 {
            return r
        }

        let x1 = x1?.value(context: context, mode: .width) ?? 0
        let y1 = y1?.value(context: context, mode: .height) ?? 0
        let x2 = x2?.value(context: context, mode: .width) ?? 0
        let y2 = y2?.value(context: context, mode: .height) ?? 0
        let length = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2))
        let lineWidth = stroke.width?.value(context: context, mode: .other) ?? 1.0
        let xmin = min(x1, x2)
        let ymin = min(y1, y2)
        if r.width > 0 {
            let origin = CGPoint(x: xmin, y: ymin - lineWidth / 2.0)
            return CGRect(origin: origin, size: CGSize(width: length, height: lineWidth))
        }
        if r.height > 0 {
            let origin = CGPoint(x: xmin - lineWidth / 2.0, y: ymin)
            return CGRect(origin: origin, size: CGSize(width: lineWidth, height: length))
        }
        return .zero
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

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(x1, forKey: .x1)
        try container.encode(y1, forKey: .y1)
        try container.encode(x1, forKey: .x2)
        try container.encode(y1, forKey: .y2)
        try container.encode(fill, forKey: .fill)
    }
}
