import CoreText
import Foundation

enum SVGLengthType: String {
    case unknown
    case number
    case percentage = "%"
    case ems = "em"
    case exs = "ex"
    case pixels = "px"
    case centimeters = "cm"
    case millimeters = "mm"
    case inches = "in"
    case points = "pt"
    case picas = "pc"
}

enum SVGLengthMode {
    case width
    case height
    case other
}

enum SVGLength {
    case pixel(CGFloat)
    case percent(CGFloat)
    case ems(CGFloat)
    case exs(CGFloat)
    case centimeters(CGFloat)
    case millimeters(CGFloat)
    case inches(CGFloat)
    case points(CGFloat)
    case picas(CGFloat)

    private static let pixelsPerInch: CGFloat = 96.0

    init(value: Double, unit: CSSUnitType) {
        switch unit {
        case .px:
            self = .pixel(value)
        case .percentage:
            self = .percent(value)
        default:
            self = .pixel(value)
        }
    }

    init?(_ description: String?) {
        guard var data = description?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        let v: SVGLength? = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            guard let value = scanner.scanNumber() else { return nil }
            let lengthType = scanner.scanLengthType()
            switch lengthType {
            case .unknown:
                return nil
            case .percentage:
                return .percent(value)
            case .ems:
                return .ems(value)
            case .exs:
                return .exs(value)
            case .centimeters:
                return .centimeters(value)
            case .millimeters:
                return .millimeters(value)
            case .inches:
                return .inches(value)
            case .points:
                return .points(value)
            case .picas:
                return .picas(value)
            case .pixels, .number:
                return .pixel(value)
            }
        }

        if let v = v {
            self = v
            return
        }
        return nil
    }

    init?(style: CSSValue?, value: String?) {
        if case let .length(length) = style {
            self = length
            return
        }
        guard var data = value?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        let v: SVGLength? = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            guard let value = scanner.scanNumber() else { return nil }
            let lengthType = scanner.scanLengthType()
            switch lengthType {
            case .unknown:
                return nil
            case .percentage:
                return .percent(value)
            case .ems:
                return .ems(value)
            case .exs:
                return .exs(value)
            case .pixels, .number:
                return .pixel(value)
            case .centimeters:
                return .centimeters(value)
            case .millimeters:
                return .millimeters(value)
            case .inches:
                return .inches(value)
            case .points:
                return .picas(value)
            case .picas:
                return .picas(value)
            }
        }

        if let v = v {
            self = v
            return
        }
        return nil
    }

    func value(context: SVGLengthContext, mode: SVGLengthMode, userSpace: Bool = true) -> CGFloat {
        switch self {
        case let .percent(percent):
            let total: CGFloat
            let size = userSpace ? context.viewBoxSize : CGSize(width: 1, height: 1)
            switch mode {
            case .height:
                total = size.height
            case .width:
                total = size.width
            case .other:
                let h = size.height
                let w = size.width
                total = sqrt(pow(w, 2) + pow(h, 2)) / sqrt(2)
            }
            return total * percent / 100.0
        case let .pixel(pixel):
            return pixel
        case let .ems(value):
            guard let font = context.font,
                  let fontSize = font.size else { return 0 }
            return value * fontSize
        case let .exs(value):
            guard let font = context.font else { return 0 }
            let xHeight = CTFontGetXHeight(font.toCTFont)
            return value * xHeight
        case let .centimeters(value):
            return value * Self.pixelsPerInch / 2.54
        case let .millimeters(value):
            return value * Self.pixelsPerInch / 25.4
        case let .inches(value):
            return value * Self.pixelsPerInch
        case let .points(value):
            return value * Self.pixelsPerInch / 72.0
        case let .picas(value):
            return value * Self.pixelsPerInch / 6.0
        }
    }
}

extension SVGLength: CustomStringConvertible {
    var description: String {
        switch self {
        case let .pixel(value): return "\(value)px"
        case let .percent(value): return "\(value)%"
        case let .ems(value): return "\(value)em"
        case let .exs(value): return "\(value)ex"
        case let .centimeters(value): return "\(value)cm"
        case let .millimeters(value): return "\(value)mm"
        case let .inches(value): return "\(value)in"
        case let .points(value): return "\(value)pt"
        case let .picas(value): return "\(value)pc"
        }
    }
}

extension SVGLength: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .pixel(v):
            try container.encode(SVGLengthType.pixels.rawValue)
            try container.encode(v)
        case let .percent(v):
            try container.encode(SVGLengthType.percentage.rawValue)
            try container.encode(v)
        case let .ems(v):
            try container.encode(SVGLengthType.ems.rawValue)
            try container.encode(v)
        case let .exs(v):
            try container.encode(SVGLengthType.exs.rawValue)
            try container.encode(v)
        case let .centimeters(v):
            try container.encode(SVGLengthType.centimeters.rawValue)
            try container.encode(v)
        case let .millimeters(v):
            try container.encode(SVGLengthType.millimeters.rawValue)
            try container.encode(v)
        case let .inches(v):
            try container.encode(SVGLengthType.inches.rawValue)
            try container.encode(v)
        case let .points(v):
            try container.encode(SVGLengthType.points.rawValue)
            try container.encode(v)
        case let .picas(v):
            try container.encode(SVGLengthType.picas.rawValue)
            try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let typeString = try container.decode(String.self)
        guard let type = SVGLengthType(rawValue: typeString) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        let value = try container.decode(Double.self)
        switch type {
        case .pixels, .number:
            self = .pixel(value)
        case .percentage:
            self = .percent(value)
        case .ems:
            self = .ems(value)
        case .exs:
            self = .ems(value)
        case .centimeters:
            self = .centimeters(value)
        case .millimeters:
            self = .millimeters(value)
        case .inches:
            self = .inches(value)
        case .points:
            self = .points(value)
        case .picas:
            self = .picas(value)
        case .unknown:
            self = .pixel(0)
        }
    }
}
