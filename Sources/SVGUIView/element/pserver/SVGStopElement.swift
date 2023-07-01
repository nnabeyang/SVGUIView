
import CoreGraphics

enum StopDimension {
    case absolute(Double)
    case percent(Double)

    var value: CGFloat {
        switch self {
        case let .absolute(v):
            return CGFloat(max(v, 0))
        case let .percent(v):
            return CGFloat(max(v, 0)) / 100.0
        }
    }
}

extension StopDimension: CustomStringConvertible {
    var description: String {
        switch self {
        case let .absolute(v):
            return v.description
        case let .percent(v):
            return "\(v)%"
        }
    }
}

struct SVGStopElement: SVGElement {
    var type: SVGElementName {
        .stop
    }

    func draw(_: SVGContext, index _: Int, depth _: Int, isRoot _: Bool) {
        fatalError()
    }

    func style(with _: CSSStyle) -> SVGElement {
        self
    }

    let offset: StopDimension
    let color: SVGFill?
    let opacity: Double
    init(attributes: [String: String]) {
        let attribute = attributes["offset", default: ""].trimmingCharacters(in: .whitespaces)
        if attribute.hasSuffix("%") {
            offset = .percent(Double(String(attribute.dropLast()).trimmingCharacters(in: .whitespaces)) ?? 0)
        } else {
            offset = .absolute(Double(attribute) ?? 0)
        }
        color = SVGFill(description: attributes["stop-color", default: "black"])
        opacity = Double(attributes["stop-opacity", default: ""].trimmingCharacters(in: .whitespaces)) ?? 1.0
    }
}

extension SVGStopElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case offset
        case color = "stop-color"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(offset.description, forKey: .offset)
        try container.encode(color, forKey: .color)
    }
}
