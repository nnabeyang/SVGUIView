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

enum SVGLength: Equatable {
    case number(CGFloat)
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

    static let pixelsPerInch: CGFloat = 96.0
    static var zeroCodePoint: UniChar {
        get { 0x30 }
        set {}
    }

    init(value: Double, unit: CSSUnitType) {
        switch unit {
        case .px:
            self = .pixel(value)
        case .percentage:
            self = .percent(value)
        case .ems:
            self = .ems(value)
        case .exs:
            self = .exs(value)
        case .mm:
            self = .millimeters(value)
        case .chs:
            self = .chs(value)
        case .ic:
            self = .ic(value)
        case .rems:
            self = .rems(value)
        case .lhs:
            self = .lhs(value)
        case .rlhs:
            self = .rlhs(value)
        default:
            self = .pixel(value)
        }
    }

    init(child: SVGLength, parent: SVGLength) {
        switch child {
        case let .percent(percent):
            switch parent {
            case let .number(value):
                self = .number(value * percent / 100.0)
            case let .pixel(value):
                self = .number(value * percent / 100.0)
            case let .percent(value):
                self = .percent(value * percent / 100.0)
            case let .ems(value):
                self = .number(value * percent / 100.0)
            case let .rems(value):
                self = .number(value * percent / 100.0)
            case let .exs(value):
                self = .number(value * percent / 100.0)
            case let .centimeters(value):
                self = .number(value * percent / 100.0)
            case let .millimeters(value):
                self = .number(value * percent / 100.0)
            case let .inches(value):
                self = .number(value * percent / 100.0)
            case let .points(value):
                self = .number(value * percent / 100.0)
            case let .picas(value):
                self = .number(value * percent / 100.0)
            case let .chs(value):
                self = .number(value * percent / 100.0)
            case let .ic(value):
                self = .number(value * percent / 100.0)
            case let .lhs(value):
                self = .number(value * percent / 100.0)
            case let .rlhs(value):
                self = .number(value * percent / 100.0)
            case let .vw(value):
                self = .number(value * percent / 100.0)
            case let .vh(value):
                self = .number(value * percent / 100.0)
            case let .vi(value):
                self = .number(value * percent / 100.0)
            case let .vb(value):
                self = .number(value * percent / 100.0)
            case let .vmin(value):
                self = .number(value * percent / 100.0)
            case let .vmax(value):
                self = .number(value * percent / 100.0)
            case let .q(value):
                self = .number(value * percent / 100.0)
            }
        default:
            self = child
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
            case .pixels:
                return .pixel(value)
            case .number:
                return .number(value)
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

    func calculatedLength(frame: CGRect, context: any SVGLengthContext, mode: SVGLengthMode, unitType: SVGUnitType = .userSpaceOnUse, isPosition: Bool = false) -> CGFloat {
        let value = value(context: context, mode: mode, unitType: unitType)
        let viewBoxSize = context.viewBoxSize
        switch mode {
        case .height:
            let dy: CGFloat
            switch unitType {
            case .userSpaceOnUse:
                return min(value, 1.2 * viewBoxSize.height)
            case .objectBoundingBox:
                dy = frame.height * value
                return isPosition ? frame.minY + dy : dy
            }
        case .width:
            let dx: CGFloat
            switch unitType {
            case .userSpaceOnUse:
                return min(value, 1.2 * viewBoxSize.width)
            case .objectBoundingBox:
                dx = frame.width * value
                return isPosition ? frame.minX + dx : dx
            }
        case .other:
            let c = sqrt(pow(viewBoxSize.width, 2) + pow(viewBoxSize.height, 2)) / sqrt(2)
            switch unitType {
            case .userSpaceOnUse:
                return min(value, 1.2 * c)
            case .objectBoundingBox:
                return c * value
            }
        }
    }

    func value(context: any SVGLengthContext, mode: SVGLengthMode, unitType: SVGUnitType = .userSpaceOnUse) -> CGFloat {
        let total: CGFloat
        if case .percent = self {
            let size: CGSize
            switch unitType {
            case .userSpaceOnUse:
                size = context.viewBoxSize
            case .objectBoundingBox:
                size = CGSize(width: 1, height: 1)
            }
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
        } else {
            total = 0
        }
        return value(total: total, context: context)
    }

    func fontValue(context: any SVGLengthContext) -> CGFloat {
        let total: CGFloat
        if case .percent = self {
            total = context.font?.sizeValue(context: context, textScale: 1.0) ?? 16.0
        } else {
            total = 0
        }
        return value(total: total, context: context)
    }

    func value(total: CGFloat, context: any SVGLengthContext) -> CGFloat {
        switch self {
        case let .percent(percent):
            return total * percent / 100.0
        case let .pixel(pixel), let .number(pixel):
            return pixel
        case let .ems(value):
            guard let font = context.font else { return 0 }
            switch font.size {
            case let .length(.ems(value)):
                let fontSize = SVGUIFont.Size.defaultFontSize
                return Self.ems(value: value, fontSize: fontSize)
            default:
                let fontSize = font.sizeValue(context: context)
                return Self.ems(value: value, fontSize: fontSize)
            }
        case let .rems(value):
            guard let font = context.rootFont else { return 0 }
            switch font.size {
            case let .length(.rems(value)):
                let fontSize = SVGUIFont.Size.defaultFontSize
                return Self.ems(value: value, fontSize: fontSize)
            default:
                let fontSize = font.sizeValue(context: context)
                return Self.ems(value: value, fontSize: fontSize)
            }
        case let .exs(value):
            guard let font = context.font else {
                return 0
            }
            switch font.size {
            case .length(.exs(value)):
                let ctFont = CTFont.standard(context: context)
                return Self.exs(value: value, ctFont: ctFont)
            default:
                let ctFont = font.ctFont(context: context)
                return Self.exs(value: value, ctFont: ctFont)
            }
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
            switch font.size {
            case .length(.chs(value)):
                let ctFont = CTFont.standard(context: context)
                return Self.chs(value: value, ctFont: ctFont)
            default:
                return Self.chs(value: value, ctFont: font.ctFont(context: context))
            }
        case let .ic(value):
            guard let font = context.font else { return 0 }
            switch font.size {
            case .length(.ic(value)):
                let ctFont = CTFont.standard(context: context)
                return Self.ic(value: value, ctFont: ctFont)
            default:
                return Self.ic(value: value, ctFont: font.ctFont(context: context))
            }
        case let .lhs(value):
            guard let font = context.font else { return 0 }
            switch font.size {
            case .length(.lhs(value)):
                let ctFont = CTFont.standard(context: context)
                return Self.lhs(value: value, ctFont: ctFont)
            default:
                let ctFont = font.ctFont(context: context)
                return Self.lhs(value: value, ctFont: ctFont)
            }
        case let .rlhs(value):
            guard let font = context.rootFont else { return 0 }
            switch font.size {
            case .length(.lhs(value)):
                let ctFont = CTFont.standard(context: context)
                return Self.lhs(value: value, ctFont: ctFont)
            default:
                let ctFont = font.ctFont(context: context)
                return Self.lhs(value: value, ctFont: ctFont)
            }
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

    private static func ems(value: CGFloat, fontSize: CGFloat) -> CGFloat {
        value * fontSize
    }

    private static func exs(value: CGFloat, ctFont: CTFont) -> CGFloat {
        let xHeight = CTFontGetXHeight(ctFont)
        return value * xHeight
    }

    private static func chs(value: CGFloat, ctFont: CTFont) -> CGFloat {
        var glyph = CGGlyph()
        CTFontGetGlyphsForCharacters(ctFont, &Self.zeroCodePoint, &glyph, 1)
        var advance: CGSize = .zero
        CTFontGetAdvancesForGlyphs(ctFont, CTFontOrientation.default, &glyph, &advance, 1)
        let width = advance == .zero ? CTFontGetSize(ctFont) / 2.0 : advance.width
        return value * width
    }

    private static func ic(value: CGFloat, ctFont: CTFont) -> CGFloat {
        value * CTFontGetSize(ctFont)
    }

    private static func lhs(value: CGFloat, ctFont: CTFont) -> CGFloat {
        let ascent = CTFontGetAscent(ctFont)
        let lineGap = CTFontGetLeading(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let lineSpacing = (ceil(ascent) + ceil(lineGap) + ceil(descent))
        return value * lineSpacing
    }
}

extension SVGLength: CustomStringConvertible {
    var description: String {
        switch self {
        case let .number(value): return "\(value)"
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
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .number(v):
            try container.encode(SVGLengthType.number.rawValue)
            try container.encode(v)
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

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let typeString = try container.decode(String.self)
        guard let type = SVGLengthType(rawValue: typeString) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        let value = try container.decode(Double.self)
        switch type {
        case .number:
            self = .number(value)
        case .pixels:
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
