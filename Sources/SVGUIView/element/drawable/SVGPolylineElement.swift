import UIKit

struct SVGPolylineElement: SVGDrawableElement {
    var type: SVGElementName {
        .polyline
    }

    let base: SVGBaseElement
    let points: SVGUIPoints

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        points = .init(description: attributes["points", default: ""])
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        points = other.points
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        points.polyline
    }
}

extension SVGPolylineElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case points
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(points, forKey: .points)
        try container.encode(fill, forKey: .fill)
    }
}
