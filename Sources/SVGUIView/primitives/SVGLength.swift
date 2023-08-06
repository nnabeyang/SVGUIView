import CoreText
import Foundation

enum SVGLengthType: String {
    case unknown
    case number
    case percentage = "%"
    case ems = "em"
    case rems = "rem"
    case exs = "ex"
    case pixels = "px"
    case centimeters = "cm"
    case millimeters = "mm"
    case inches = "in"
    case points = "pt"
    case picas = "pc"
    case chs = "ch"
    case ic
    case lhs = "lh"
    case rlhs = "rlh"
    case vw
    case vh
    case vi
    case vb
    case vmin
    case vmax
    case q = "Q"
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
    case rems(CGFloat)
    case exs(CGFloat)
    case centimeters(CGFloat)
    case millimeters(CGFloat)
    case inches(CGFloat)
    case points(CGFloat)
    case picas(CGFloat)
    case chs(CGFloat)
    case ic(CGFloat)
    case lhs(CGFloat)
    case rlhs(CGFloat)
    case vw(CGFloat)
    case vh(CGFloat)
    case vi(CGFloat)
    case vb(CGFloat)
    case vmin(CGFloat)
    case vmax(CGFloat)
    case q(CGFloat)

    private static let pixelsPerInch: CGFloat = 96.0
    private static var zeroCodePoint: UniChar = 0x30

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
            case .rems:
                return .rems(value)
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
            case .chs:
                return .chs(value)
            case .ic:
                return .ic(value)
            case .lhs:
                return .lhs(value)
            case .rlhs:
                return .rlhs(value)
            case .vw:
                return .vw(value)
            case .vh:
                return .vh(value)
            case .vi:
                return .vi(value)
            case .vb:
                return .vb(value)
            case .vmin:
                return .vmin(value)
            case .vmax:
                return .vmax(value)
            case .q:
                return .q(value)
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
            case .rems:
                return .rems(value)
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
            case .chs:
                return .chs(value)
            case .ic:
                return .ic(value)
            case .lhs:
                return .lhs(value)
            case .rlhs:
                return .rlhs(value)
            case .vw:
                return .vw(value)
            case .vh:
                return .vh(value)
            case .vi:
                return .vi(value)
            case .vb:
                return .vb(value)
            case .vmin:
                return .vmin(value)
            case .vmax:
                return .vmax(value)
            case .q:
                return .q(value)
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
        case let .rems(value):
            guard let font = context.rootFont,
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
        case let .chs(value):
            guard let font = context.font else { return 0 }
            let ctFont = font.toCTFont
            var glyph = CGGlyph()
            CTFontGetGlyphsForCharacters(ctFont, &Self.zeroCodePoint, &glyph, 1)
            var advance: CGSize = .zero
            CTFontGetAdvancesForGlyphs(ctFont, CTFontOrientation.default, &glyph, &advance, 1)
            let width = advance == .zero ? CTFontGetSize(ctFont) / 2.0 : advance.width
            return value * width
        case let .ic(value):
            guard let font = context.font else { return 0 }
            return value * CTFontGetSize(font.toCTFont)
        case let .lhs(value):
            guard let font = context.font else { return 0 }
            let ctFont = font.toCTFont
            let ascent = CTFontGetAscent(ctFont)
            let lineGap = CTFontGetLeading(ctFont)
            let descent = CTFontGetDescent(ctFont)
            let lineSpacing = (ceil(ascent) + ceil(lineGap) + ceil(descent))
            return value * lineSpacing
        case let .rlhs(value):
            guard let font = context.rootFont else { return 0 }
            let ctFont = font.toCTFont
            let ascent = CTFontGetAscent(ctFont)
            let lineGap = CTFontGetLeading(ctFont)
            let descent = CTFontGetDescent(ctFont)
            let lineSpacing = (ceil(ascent) + ceil(lineGap) + ceil(descent))
            return value * lineSpacing
        case let .vw(value):
            return value * context.viewPort.width / 100.0
        case let .vh(value):
            return value * context.viewPort.height / 100.0
        case let .vi(value):
            let viewPort = context.viewPort
            let writingMode = context.writingMode ?? .horizontalTB
            let scale: CGFloat
            switch writingMode {
            case .horizontalTB:
                scale = viewPort.width / 100.0
            case .verticalLR, .verticalRL:
                scale = viewPort.height / 100.0
            }
            return value * scale
        case let .vb(value):
            let viewPort = context.viewPort
            let writingMode = context.writingMode ?? .horizontalTB
            let scale: CGFloat
            switch writingMode {
            case .horizontalTB:
                scale = viewPort.height / 100.0
            case .verticalLR, .verticalRL:
                scale = viewPort.width / 100.0
            }
            return value * scale
        case let .vmin(value):
            return value * min(context.viewPort.width, context.viewPort.height) / 100.0
        case let .vmax(value):
            return value * max(context.viewPort.width, context.viewPort.height) / 100.0
        case let .q(value):
            return value * Self.pixelsPerInch / (25.4 * 4.0)
        }
    }
}

extension SVGLength: CustomStringConvertible {
    var description: String {
        switch self {
        case let .pixel(value): return "\(value)px"
        case let .percent(value): return "\(value)%"
        case let .ems(value): return "\(value)em"
        case let .rems(value): return "\(value)rem"
        case let .exs(value): return "\(value)ex"
        case let .centimeters(value): return "\(value)cm"
        case let .millimeters(value): return "\(value)mm"
        case let .inches(value): return "\(value)in"
        case let .points(value): return "\(value)pt"
        case let .picas(value): return "\(value)pc"
        case let .chs(value): return "\(value)ch"
        case let .ic(value): return "\(value)ic"
        case let .lhs(value): return "\(value)lh"
        case let .rlhs(value): return "\(value)rlh"
        case let .vw(value): return "\(value)vw"
        case let .vh(value): return "\(value)vh"
        case let .vi(value): return "\(value)vi"
        case let .vb(value): return "\(value)vb"
        case let .vmin(value): return "\(value)vmin"
        case let .vmax(value): return "\(value)vmax"
        case let .q(value): return "\(value)Q"
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
        case let .rems(v):
            try container.encode(SVGLengthType.rems.rawValue)
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
        case let .chs(v):
            try container.encode(SVGLengthType.chs.rawValue)
            try container.encode(v)
        case let .ic(v):
            try container.encode(SVGLengthType.ic.rawValue)
            try container.encode(v)
        case let .lhs(v):
            try container.encode(SVGLengthType.lhs.rawValue)
            try container.encode(v)
        case let .rlhs(v):
            try container.encode(SVGLengthType.rlhs.rawValue)
            try container.encode(v)
        case let .vw(v):
            try container.encode(SVGLengthType.vw.rawValue)
            try container.encode(v)
        case let .vh(v):
            try container.encode(SVGLengthType.vh.rawValue)
            try container.encode(v)
        case let .vi(v):
            try container.encode(SVGLengthType.vi.rawValue)
            try container.encode(v)
        case let .vb(v):
            try container.encode(SVGLengthType.vb.rawValue)
            try container.encode(v)
        case let .vmin(v):
            try container.encode(SVGLengthType.vmin.rawValue)
            try container.encode(v)
        case let .vmax(v):
            try container.encode(SVGLengthType.vmax.rawValue)
            try container.encode(v)
        case let .q(v):
            try container.encode(SVGLengthType.q.rawValue)
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
        case .rems:
            self = .rems(value)
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
        case .chs:
            self = .chs(value)
        case .ic:
            self = .ic(value)
        case .lhs:
            self = .lhs(value)
        case .rlhs:
            self = .rlhs(value)
        case .vw:
            self = .vw(value)
        case .vh:
            self = .vh(value)
        case .vi:
            self = .vi(value)
        case .vb:
            self = .vb(value)
        case .vmin:
            self = .vmin(value)
        case .vmax:
            self = .vmax(value)
        case .q:
            self = .q(value)
        case .unknown:
            self = .pixel(0)
        }
    }
}
