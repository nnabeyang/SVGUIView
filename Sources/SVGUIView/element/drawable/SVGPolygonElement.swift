import UIKit

struct SVGPolygonElement: SVGDrawableElement {
    var type: SVGElementName {
        .polygon
    }

    let base: SVGBaseElement
    let points: SVGUIPoints

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        points = .init(description: attributes["points", default: ""])
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        points = other.points
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        points.polygon.map {
            $0.apply(scale(context: context))
            return $0
        }
    }
}

extension SVGPolygonElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case points
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(points, forKey: .points)
        try container.encode(fill, forKey: .fill)
    }
}
