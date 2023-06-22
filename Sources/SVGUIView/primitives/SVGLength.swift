import Foundation

enum SVGLength {
    case pixel(CGFloat)
    case percent(CGFloat)

    init(value: Double, unit: CSSUnitType) {
        precondition(value > 0)
        switch unit {
        case .px:
            self = .pixel(value)
        case .percentage:
            self = .percent(value)
        default:
            self = .pixel(value)
        }
    }

    init?(_ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }

        if value.hasSuffix("%"),
           let value = Double(value.dropLast())
        {
            guard value > 0 else { return nil }
            self = .percent(CGFloat(value))
            return
        }
        if value.hasSuffix("px"), let value = Double(value.dropLast(2)) {
            guard value > 0 else { return nil }
            self = .pixel(CGFloat(value))
            return
        }
        if let value = Double(value), value > 0 {
            self = .pixel(CGFloat(value))
            return
        }
        return nil
    }

    func value(total: CGFloat) -> CGFloat {
        switch self {
        case let .percent(percent):
            return total * percent / 100.0
        case let .pixel(pixel):
            return pixel
        }
    }
}

extension SVGLength: CustomStringConvertible {
    var description: String {
        switch self {
        case let .pixel(value): return "\(value)px"
        case let .percent(value): return "\(value)%"
        }
    }
}

extension SVGLength: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .pixel(v):
            try container.encode(ElementLengthType.pixel.rawValue)
            try container.encode(v)
        case let .percent(v):
            try container.encode(ElementLengthType.percent.rawValue)
            try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let typeString = try container.decode(String.self)
        guard let type = ElementLengthType(rawValue: typeString) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        let value = try container.decode(Double.self)
        switch type {
        case .pixel:
            self = .pixel(value)
        case .percent:
            self = .percent(value)
        }
    }
}
