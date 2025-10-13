import UIKit

enum SVGFillType: String {
    case rgb
    case rgba
    case url
    case inherit
    case current = "currentcolor"
}

enum SVGColorType: String {
    case named
    case hex
    case rgb
    case rgba
    case url
    case inherit
    case current = "currentcolor"
}

protocol SVGUIColor: CustomStringConvertible, Codable {
    func toUIColor(opacity: Double) -> UIColor?
    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { get }
}

struct SVGColorName: SVGUIColor {
    let name: String
    func toUIColor(opacity: Double) -> UIColor? {
        guard let value = Self.colors[name.lowercased()] else { return nil }
        let t = value & 0xFF
        let b = (value >> 8) & 0xFF
        let g = (value >> 16) & 0xFF
        let r = (value >> 24) & 0xFF

        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: (1.0 - CGFloat(t) / 255.0) * opacity
        )
    }

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let value = Self.colors[name.lowercased()] ?? 0
        let t = UInt8(value & 0xFF)
        let blue = CGFloat((value >> 8) & 0xFF)
        let green = CGFloat((value >> 16) & 0xFF)
        let red = CGFloat((value >> 24) & 0xFF)
        let alpha = CGFloat(0xFF - t)
        return (red: red, green: green, blue: blue, alpha: alpha)
    }

    private static let colors: [String: UInt64] = [
        "aliceblue": 0xF0F8_FF00,
        "alpha": 0x0000_00FF,
        "antiquewhite": 0xFAEB_D700,
        "aqua": 0x00FF_FF00,
        "aquamarine": 0x7FFF_D400,
        "azure": 0xF0FF_FF00,
        "beige": 0xF5F5_DC00,
        "bisque": 0xFFE4_C400,
        "black": 0x0000_0000,
        "blanchedalmond": 0xFFEB_CD00,
        "blue": 0x0000_FF00,
        "blueviolet": 0x8A2B_E200,
        "brown": 0xA52A_2A00,
        "burlywood": 0xDEB8_8700,
        "cadetblue": 0x5F9E_A000,
        "chartreuse": 0x7FFF_0000,
        "chocolate": 0xD269_1E00,
        "coral": 0xFF7F_5000,
        "cornflowerblue": 0x6495_ED00,
        "cornsilk": 0xFFF8_DC00,
        "crimson": 0xDC14_3C00,
        "cyan": 0x00FF_FF00,
        "darkblue": 0x0000_8B00,
        "darkcyan": 0x008B_8B00,
        "darkgoldenrod": 0xB886_0B00,
        "darkgray": 0xA9A9_A900,
        "darkgrey": 0xA9A9_A900,
        "darkgreen": 0x0064_0000,
        "darkkhaki": 0xBDB7_6B00,
        "darkmagenta": 0x8B00_8B00,
        "darkolivegreen": 0x556B_2F00,
        "darkorange": 0xFF8C_0000,
        "darkorchid": 0x9932_CC00,
        "darkred": 0x8B00_0000,
        "darksalmon": 0xE996_7A00,
        "darkseagreen": 0x8FBC_8F00,
        "darkslateblue": 0x483D_8B00,
        "darkslategray": 0x2F4F_4F00,
        "darkslategrey": 0x2F4F_4F00,
        "darkturquoise": 0x00CE_D100,
        "darkviolet": 0x9400_D300,
        "deeppink": 0xFF14_9300,
        "deepskyblue": 0x00BF_FF00,
        "dimgray": 0x6969_6900,
        "dimgrey": 0x6969_6900,
        "dodgerblue": 0x1E90_FF00,
        "firebrick": 0xB222_2200,
        "floralwhite": 0xFFFA_F000,
        "forestgreen": 0x228B_2200,
        "fuchsia": 0xFF00_FF00,
        "gainsboro": 0xDCDC_DC00,
        "ghostwhite": 0xF8F8_FF00,
        "gold": 0xFFD7_0000,
        "goldenrod": 0xDAA5_2000,
        "gray": 0x8080_8000,
        "grey": 0x8080_8000,
        "green": 0x0080_0000,
        "greenyellow": 0xADFF_2F00,
        "honeydew": 0xF0FF_F000,
        "hotpink": 0xFF69_B400,
        "indianred": 0xCD5C_5C00,
        "indigo": 0x4B00_8200,
        "ivory": 0xFFFF_F000,
        "khaki": 0xF0E6_8C00,
        "lavender": 0xE6E6_FA00,
        "lavenderblush": 0xFFF0_F500,
        "lawngreen": 0x7CFC_0000,
        "lemonchiffon": 0xFFFA_CD00,
        "lightblue": 0xADD8_E600,
        "lightcoral": 0xF080_8000,
        "lightcyan": 0xE0FF_FF00,
        "lightgoldenrodyellow": 0xFAFA_D200,
        "lightgray": 0xD3D3_D300,
        "lightgrey": 0xD3D3_D300,
        "lightgreen": 0x90EE_9000,
        "lightpink": 0xFFB6_C100,
        "lightsalmon": 0xFFA0_7A00,
        "lightseagreen": 0x20B2_AA00,
        "lightskyblue": 0x87CE_FA00,
        "lightslateblue": 0x8470_FF00,
        "lightslategray": 0x7788_9900,
        "lightslategrey": 0x7788_9900,
        "lightsteelblue": 0xB0C4_DE00,
        "lightyellow": 0xFFFF_E000,
        "lime": 0x00FF_0000,
        "limegreen": 0x32CD_3200,
        "linen": 0xFAF0_E600,
        "magenta": 0xFF00_FF00,
        "maroon": 0x8000_0000,
        "mediumaquamarine": 0x66CD_AA00,
        "mediumblue": 0x0000_CD00,
        "mediumorchid": 0xBA55_D300,
        "mediumpurple": 0x9370_DB00,
        "mediumseagreen": 0x3CB3_7100,
        "mediumslateblue": 0x7B68_EE00,
        "mediumspringgreen": 0x00FA_9A00,
        "mediumturquoise": 0x48D1_CC00,
        "mediumvioletred": 0xC715_8500,
        "midnightblue": 0x1919_7000,
        "mintcream": 0xF5FF_FA00,
        "mistyrose": 0xFFE4_E100,
        "moccasin": 0xFFE4_B500,
        "navajowhite": 0xFFDE_AD00,
        "navy": 0x0000_8000,
        "oldlace": 0xFDF5_E600,
        "olive": 0x8080_0000,
        "olivedrab": 0x6B8E_2300,
        "orange": 0xFFA5_0000,
        "orangered": 0xFF45_0000,
        "orchid": 0xDA70_D600,
        "palegoldenrod": 0xEEE8_AA00,
        "palegreen": 0x98FB_9800,
        "paleturquoise": 0xAFEE_EE00,
        "palevioletred": 0xDB70_9300,
        "papayawhip": 0xFFEF_D500,
        "peachpuff": 0xFFDA_B900,
        "peru": 0xCD85_3F00,
        "pink": 0xFFC0_CB00,
        "plum": 0xDDA0_DD00,
        "powderblue": 0xB0E0_E600,
        "purple": 0x8000_8000,
        "rebeccapurple": 0x6633_9900,
        "red": 0xFF00_0000,
        "rosybrown": 0xBC8F_8F00,
        "royalblue": 0x4169_E100,
        "saddlebrown": 0x8B45_1300,
        "salmon": 0xFA80_7200,
        "sandybrown": 0xF4A4_6000,
        "seagreen": 0x2E8B_5700,
        "seashell": 0xFFF5_EE00,
        "sienna": 0xA052_2D00,
        "silver": 0xC0C0_C000,
        "skyblue": 0x87CE_EB00,
        "slateblue": 0x6A5A_CD00,
        "slategray": 0x7080_9000,
        "slategrey": 0x7080_9000,
        "snow": 0xFFFA_FA00,
        "springgreen": 0x00FF_7F00,
        "steelblue": 0x4682_B400,
        "tan": 0xD2B4_8C00,
        "teal": 0x0080_8000,
        "thistle": 0xD8BF_D800,
        "tomato": 0xFF63_4700,
        "transparent": 0x0000_00FF,
        "turquoise": 0x40E0_D000,
        "violet": 0xEE82_EE00,
        "violetred": 0xD020_9000,
        "wheat": 0xF5DE_B300,
        "white": 0xFFFF_FF00,
        "whitesmoke": 0xF5F5_F500,
        "yellow": 0xFFFF_0000,
        "yellowgreen": 0x9ACD_3200,
    ]
}

extension SVGColorName: Codable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(SVGColorType.named.rawValue)
        try container.encode(name)
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard let type = try SVGColorType(rawValue: container.decode(String.self)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        precondition(type == .named)
        name = try container.decode(String.self)
    }
}

extension SVGColorName: CustomStringConvertible {
    var description: String {
        name
    }
}

struct SVGHexColor: SVGUIColor {
    let hex: String
    let value: UInt64
    let isShort: Bool
    let hasAlpha: Bool
    init?(hex: String) {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        self.hex = hex
        self.value = value
        let count = hex.count
        isShort = count <= 4
        hasAlpha = count == 4 || count == 8
    }

    func toUIColor(opacity: Double) -> UIColor? {
        let base = CGFloat(isShort ? 0xF : 0xFF)
        let (r, g, b, a) = rgba
        return UIColor(
            red: CGFloat(r) / base,
            green: CGFloat(g) / base,
            blue: CGFloat(b) / base,
            alpha: CGFloat(a) / base * opacity
        )
    }

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let shift = isShort ? 4 : 8
        let mask: UInt64 = isShort ? 0xF : 0xFF
        let alpha = CGFloat(hasAlpha ? ((value >> (shift * 0)) & mask) : mask)
        let blue = CGFloat((value >> (shift * (hasAlpha ? 1 : 0))) & mask)
        let green = CGFloat((value >> (shift * (hasAlpha ? 2 : 1))) & mask)
        let red = CGFloat((value >> (shift * (hasAlpha ? 3 : 2))) & mask)
        return (red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension SVGHexColor: Codable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(SVGColorType.hex.rawValue)
        try container.encode(hex)
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard let type = try SVGColorType(rawValue: container.decode(String.self)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        precondition(type == .hex)
        let hex = try container.decode(String.self)
        guard let color = SVGHexColor(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        self = color
    }
}

extension SVGHexColor: CustomStringConvertible {
    var description: String {
        "#\(value)"
    }
}

enum ColorDimentionName: String {
    case absolute
    case percent
}

enum ColorDimension {
    case absolute(Double)
    case percent(Double)

    var value: CGFloat {
        switch self {
        case let .absolute(v):
            return CGFloat(max(v, 0))
        case let .percent(v):
            return CGFloat(max(v, 0)) / 100.0 * 255.0
        }
    }
}

extension ColorDimension: Codable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .absolute(v):
            try container.encode(ColorDimentionName.absolute.rawValue)
            try container.encode(v)
        case let .percent(v):
            try container.encode(ColorDimentionName.percent.rawValue)
            try container.encode(v)
        }
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard let type = try ColorDimentionName(rawValue: container.decode(String.self)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        let value = try container.decode(Double.self)
        switch type {
        case .absolute:
            self = .absolute(value)
        case .percent:
            self = .percent(value)
        }
    }
}

extension ColorDimension: CustomStringConvertible {
    var description: String {
        switch self {
        case let .absolute(v):
            return v.description
        case let .percent(v):
            return "\(v)%"
        }
    }
}

struct SVGRGBColor: SVGUIColor {
    let r: ColorDimension
    let g: ColorDimension
    let b: ColorDimension
    func toUIColor(opacity: Double) -> UIColor? {
        UIColor(
            red: r.value / 255.0,
            green: g.value / 255.0,
            blue: b.value / 255.0,
            alpha: opacity
        )
    }

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        (red: r.value, green: g.value, blue: b.value, alpha: 255.0)
    }
}

extension SVGRGBColor: Codable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(SVGColorType.rgb.rawValue)
        try container.encode(r)
        try container.encode(g)
        try container.encode(b)
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard let type = try SVGColorType(rawValue: container.decode(String.self)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        precondition(type == .rgb)
        r = try container.decode(ColorDimension.self)
        g = try container.decode(ColorDimension.self)
        b = try container.decode(ColorDimension.self)
    }
}

extension SVGRGBColor: CustomStringConvertible {
    var description: String {
        "rgb(\(r), \(g), \(b))"
    }
}

struct SVGRGBAColor: SVGUIColor {
    let r: ColorDimension
    let g: ColorDimension
    let b: ColorDimension
    let a: Double
    func toUIColor(opacity: Double) -> UIColor? {
        UIColor(
            red: r.value / 255.0,
            green: g.value / 255.0,
            blue: b.value / 255.0,
            alpha: CGFloat(a) * opacity
        )
    }

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        (red: r.value, green: g.value, blue: b.value, alpha: a * 255.0)
    }
}

extension SVGRGBAColor: Codable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(SVGColorType.rgba.rawValue)
        try container.encode(r)
        try container.encode(g)
        try container.encode(b)
        try container.encode(a)
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard let type = try SVGColorType(rawValue: container.decode(String.self)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        precondition(type == .rgba)
        r = try container.decode(ColorDimension.self)
        g = try container.decode(ColorDimension.self)
        b = try container.decode(ColorDimension.self)
        a = try container.decode(Double.self)
    }
}

extension SVGRGBAColor: CustomStringConvertible {
    var description: String {
        "rgba(\(r), \(g), \(b), \(a))"
    }
}
