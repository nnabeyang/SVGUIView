import Foundation
import _CShims

struct SVGAttributeScanner {
    var reader: BufferReader

    init(bytes: BufferView<UInt8>) {
        reader = BufferReader(bytes: bytes)
    }

    mutating func consume(ascii: UInt8) -> Bool {
        guard let ch = reader.consumeWhitespace(),
              ch == ascii else { return false }
        reader.advance()
        return true
    }

    mutating func scanIdentity() -> String? {
        if reader.isEOF { return nil }
        return consumeName()
    }

    mutating func consumeName() -> String {
        let ch = reader.peek()
        precondition(ch.isName)
        let start = reader.readIndex
        var size = 0
        while true {
            let c = reader.peek(offset: size)
            guard c > 0 else {
                reader.moveReaderIndex(forwardBy: size)
                let end = reader.readIndex
                return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
            }
            if c.isName {
                size += 1
                continue
            }
            reader.moveReaderIndex(forwardBy: size)
            let end = reader.readIndex
            return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
        }
    }

    mutating func consumeString() -> String {
        let endingCodePoint = reader.peek()
        precondition(endingCodePoint == UInt8(ascii: "'") || endingCodePoint == UInt8(ascii: "\""))
        _ = reader.read()
        let start = reader.readIndex
        var size = 0
        while !reader.isEOF {
            let c = reader.peek(offset: size)
            guard c != endingCodePoint else {
                break
            }
            size += 1
        }
        reader.moveReaderIndex(forwardBy: size + 1)
        let end = reader.readIndex.advanced(by: -1)
        return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
    }

    mutating func scanNumber() -> Double? {
        let ch = reader.peek()
        guard ch > 0 else { return nil }
        switch ch {
        case asciiNumbers, UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."):
            break
        default:
            return nil
        }
        let start = reader.readIndex
        reader.skipNumber()
        let end = reader.readIndex
        return Double(prevalidatedBuffer: reader.bytes[start ..< end])
    }

    mutating func scanBool() -> Bool? {
        guard let ascii = reader.read() else { return nil }
        switch ascii {
        case UInt8(ascii: "0"): return false
        case UInt8(ascii: "1"): return true
        default:
            return nil
        }
    }

    @discardableResult
    mutating func consumeWhitespaceIfNext(_ ch: UInt8) -> UInt8? {
        let cc = reader.consumeWhitespace()
        if let cc = cc, cc == ch {
            reader.advance()
            return reader.consumeWhitespace()
        }
        return cc
    }
}

// for d attribute of path tag
extension SVGAttributeScanner {
    mutating func scanPathSegments() -> [any PathSegment] {
        var segments = [any PathSegment]()
        while let segment = scanPathSegment() {
            segments.append(segment)
        }
        return segments
    }

    mutating func scanPoints() -> [CGPoint] {
        var points = [CGPoint]()
        while !reader.isEOF {
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let x = scanNumber() else { break }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let y = scanNumber() else { break }
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    mutating func readSegmentType() -> PathSegmentType? {
        guard let ch = reader.consumeWhitespace(),
              let type = PathSegmentType(rawValue: ch) else { return nil }
        reader.advance()
        return type
    }

    mutating func scanPathSegment() -> (any PathSegment)? {
        guard let type = readSegmentType() else { return nil }
        switch type {
        case .M, .m:
            var args = [MPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(MPathArgument(isMoved: !args.isEmpty, x: x, y: y))
            }
            if args.isEmpty { return nil }
            return MPathSegment(type: type, args: args)
        case .Z, .z:
            return ZPathSegment(type: type, args: [])
        case .L, .l:
            var args = [LPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(LPathArgument(x: x, y: y))
            }
            if args.isEmpty { return nil }
            return LPathSegment(type: type, args: args)
        case .H, .h:
            var args = [LPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                args.append(LPathArgument(x: x, y: nil))
            }
            if args.isEmpty { return nil }
            return HPathSegment(type: type, args: args)
        case .V, .v:
            var args = [LPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(LPathArgument(x: nil, y: y))
            }
            if args.isEmpty { return nil }
            return VPathSegment(type: type, args: args)
        case .C, .c:
            var args = [CPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x1 = scanNumber() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y1 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x2 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y2 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(CPathArgument(x1: x1, y1: y1, x2: x2, y2: y2, x: x, y: y))
            }
            if args.isEmpty {
                return nil
            }
            return CPathSegment(type: type, args: args)
        case .S, .s:
            var args = [CPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x2 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y2 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(CPathArgument(x1: nil, y1: nil, x2: x2, y2: y2, x: x, y: y))
            }
            if args.isEmpty { return nil }
            return SPathSegment(type: type, args: args)
        case .Q, .q:
            var args = [QPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x1 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y1 = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(QPathArgument(x1: x1, y1: y1, x: x, y: y))
            }
            if args.isEmpty { return nil }
            return QPathSegment(type: type, args: args)
        case .T, .t:
            var args = [QPathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else { break }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { break }
                args.append(QPathArgument(x1: nil, y1: nil, x: x, y: y))
            }
            if args.isEmpty { return nil }
            return TPathSegment(type: type, args: args)
        case .A, .a:
            var args = [APathArgument]()
            while !reader.isEOF {
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let rx = scanNumber() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let ry = scanNumber() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let angle = scanNumber() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let largeArc = scanBool() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let sweep = scanBool() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let x = scanNumber() else {
                    break
                }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else {
                    break
                }
                args.append(APathArgument(rx: rx, ry: ry, angle: angle, largeArc: largeArc, sweep: sweep, x: x, y: y))
            }
            if args.isEmpty { return nil }
            return APathSegment(type: type, args: args)
        }
    }
}

// for font attributes
extension SVGAttributeScanner {
    private static let familyNames = [
        "cursive",
        "fantasy",
        "monospace",
        "sans-serif",
        "serif",
        "standard",
    ]

    mutating func scanFontFamilies() -> [String] {
        var families = [String]()
        guard reader.consumeWhitespace() != nil else { return families }
        while !reader.isEOF {
            let family: String
            let ch = reader.peek()
            if ch == UInt8(ascii: "\"") || ch == UInt8(ascii: "'") {
                family = consumeString()
            } else {
                family = consumeName()
            }
            let prefix = Self.familyNames.contains(family) ? "-webkit-" : ""
            families.append("\(prefix)\(family)")
            consumeWhitespaceIfNext(UInt8(ascii: ","))
        }
        return families
    }
}

// for stroke attribute
extension SVGAttributeScanner {
    mutating func scanDashes() -> [CGFloat] {
        var dashes = [CGFloat]()
        guard reader.consumeWhitespace() != nil else { return dashes }
        while !reader.isEOF {
            guard let r = scanNumber() else { return dashes }
            dashes.append(CGFloat(r))
            consumeWhitespaceIfNext(UInt8(ascii: ","))
        }
        return dashes
    }

    mutating func scanHex() -> String? {
        guard consume(ascii: UInt8(ascii: "#")) else { return nil }
        let start = reader.readIndex
        reader.skipHex()
        let end = reader.readIndex
        guard start != end else { return nil }
        return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
    }
}

// for transform attribute
extension SVGAttributeScanner {
    mutating func scanTransform() -> [any TransformOperator] {
        var ops = [any TransformOperator]()
        while let op = scanSingleTransform() {
            ops.append(op)
        }
        return ops
    }

    mutating func scanSingleTransform() -> (any TransformOperator)? {
        consumeWhitespaceIfNext(UInt8(ascii: ","))
        if reader.isEOF { return nil }
        guard let ident = scanIdentity(),
              let name = TransformType(rawValue: ident)
        else {
            return nil
        }
        if !consume(ascii: UInt8(ascii: "(")) {
            return nil
        }
        _ = reader.consumeWhitespace()
        let op: any TransformOperator
        switch name {
        case .translate:
            guard let x = scanNumber() else { return nil }
            let ch = consumeWhitespaceIfNext(UInt8(ascii: ","))
            let y = ch == UInt8(ascii: ")") ? 0 : scanNumber() ?? 0
            op = TranslateOperator(x: x, y: y)
        case .scale:
            guard let x = scanNumber() else { return nil }
            let ch = consumeWhitespaceIfNext(UInt8(ascii: ","))
            let y = ch == UInt8(ascii: ")") ? x : scanNumber() ?? x
            op = ScaleOperator(x: x, y: y)
        case .rotate:
            guard let angle = scanNumber() else { return nil }
            let ch = consumeWhitespaceIfNext(UInt8(ascii: ","))
            if ch == UInt8(ascii: ")") {
                op = RotateOperator(angle: angle, origin: nil)
            } else {
                guard let x = scanNumber() else { return nil }
                consumeWhitespaceIfNext(UInt8(ascii: ","))
                guard let y = scanNumber() else { return nil }
                op = RotateOperator(angle: angle, origin: CGPoint(x: x, y: y))
            }
        case .skewX:
            guard let angle = scanNumber() else { return nil }
            op = SkewXOperator(angle: angle)
        case .skewY:
            guard let angle = scanNumber() else { return nil }
            op = SkewYOperator(angle: angle)
        case .matrix:
            guard let a = scanNumber() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let b = scanNumber() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let c = scanNumber() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let d = scanNumber() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let tx = scanNumber() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let ty = scanNumber() else { return nil }
            op = MatrixOperator(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
        }

        if !consume(ascii: UInt8(ascii: ")")) {
            return nil
        }
        return op
    }
}

// for fill/color attribute
extension SVGAttributeScanner {
    mutating func scanColorDimension() -> ColorDimension? {
        guard let value = scanNumber() else { return nil }
        if let ch = reader.consumeWhitespace(), ch == UInt8(ascii: "%") {
            reader.advance()
            return .percent(value)
        } else {
            return .absolute(value)
        }
    }

    mutating func scanFill(opacity: SVGOpacity? = nil) -> SVGFill? {
        guard let ascii = reader.consumeWhitespace() else { return nil }
        if ascii == UInt8(ascii: "#") {
            guard let hex = scanHex() else { return nil }
            return .color(color: SVGHexColor(hex: hex), opacity: opacity)
        }

        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGFillType(rawValue: name.lowercased()) else {
            _ = reader.consumeWhitespace()
            return reader.isEOF ?
                .color(color: SVGColorName(name: name), opacity: opacity) :
                .color(color: SVGColorName(name: "black"), opacity: opacity)
        }
        switch type {
        case .current:
            return .current
        case .inherit:
            return .inherit
        case .rgb, .rgba:
            guard let color = scanColor(type: type) else { return nil }
            return .color(color: color, opacity: opacity)
        case .url:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: "#"))
            guard let id = scanIdentity() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return .url(url: id, opacity: opacity)
        }
    }

    mutating func scanColor() -> (any SVGUIColor)? {
        guard let ascii = reader.consumeWhitespace() else { return nil }
        if ascii == UInt8(ascii: "#") {
            guard let hex = scanHex() else { return nil }
            return SVGHexColor(hex: hex)
        }

        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGFillType(rawValue: name) else {
            return SVGColorName(name: name)
        }
        return scanColor(type: type)
    }

    private mutating func scanColor(type: SVGFillType) -> (any SVGUIColor)? {
        switch type {
        case .rgb:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let r = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let g = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let b = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return SVGRGBColor(r: r, g: g, b: b)
        case .rgba:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let r = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let g = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let b = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let a = scanNumber() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return SVGRGBAColor(r: r, g: g, b: b, a: a)
        case .url, .inherit, .current:
            return nil
        }
    }

    static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanColor()
        }
    }
}

extension SVGAttributeScanner {
    mutating func scanStdDeviation() -> StdDeviation? {
        _ = reader.consumeWhitespace()
        guard let x = scanNumber() else { return nil }
        _ = reader.consumeWhitespace()
        guard let y = scanNumber() else { return .iso(SVGLength(value: x, unit: .number)) }
        _ = reader.consumeWhitespace()
        if reader.isEOF {
            return .hetero(x: SVGLength(value: x, unit: .number),
                           y: SVGLength(value: y, unit: .number))
        }
        return nil
    }
}

// for preserveAspectRatio attribute
extension SVGAttributeScanner {
    mutating func scanPreserveAspectRatio() -> PreserveAspectRatio? {
        _ = reader.consumeWhitespace()
        if reader.isEOF { return nil }
        guard let alignValue = scanIdentity(),
              let type = PreserveAspectRatio.AlignType(rawValue: alignValue)
        else {
            return nil
        }
        _ = reader.consumeWhitespace()
        let option: PreserveAspectRatio.Option = {
            guard !reader.isEOF,
                  let optionValue = scanIdentity()
            else {
                return .meet
            }
            return PreserveAspectRatio.Option(rawValue: optionValue) ?? .meet
        }()
        switch type {
        case .xMinYMin:
            return .normal(x: .min, y: .min, option: option)
        case .xMidYMin:
            return .normal(x: .mid, y: .min, option: option)
        case .xMaxYMin:
            return .normal(x: .max, y: .min, option: option)
        case .xMinYMid:
            return .normal(x: .min, y: .mid, option: option)
        case .xMidYMid:
            return .normal(x: .mid, y: .mid, option: option)
        case .xMaxYMid:
            return .normal(x: .max, y: .mid, option: option)
        case .xMinYMax:
            return .normal(x: .min, y: .max, option: option)
        case .xMidYMax:
            return .normal(x: .mid, y: .max, option: option)
        case .xMaxYMax:
            return .normal(x: .max, y: .max, option: option)
        case .none:
            return PreserveAspectRatio.none
        }
    }
}

extension SVGAttributeScanner {
    mutating func scanClipPath() -> SVGClipPath? {
        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGClipPathType(rawValue: name.lowercased()) else {
            return nil
        }
        switch type {
        case .none:
            return SVGClipPath.none
        case .url:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: "#"))
            guard let id = scanIdentity() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return .url(url: id)
        }
    }
}

extension SVGAttributeScanner {
    mutating func scanMask() -> SVGMask? {
        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGClipPathType(rawValue: name.lowercased()) else {
            return nil
        }
        switch type {
        case .none:
            return SVGMask.none
        case .url:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: "#"))
            guard let id = scanIdentity() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return .url(url: id)
        }
    }
}

extension SVGAttributeScanner {
    mutating func scanFilter() -> SVGFilter? {
        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGFilterType(rawValue: name.lowercased()) else {
            return nil
        }
        switch type {
        case .none:
            return SVGFilter.none
        case .url:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: "#"))
            guard let id = scanIdentity() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return .url(url: id)
        }
    }
}

// for svg length
extension SVGAttributeScanner {
    mutating func scanLengthType() -> SVGLengthType {
        if reader.isEOF {
            return .number
        }
        guard let first = reader.read() else { return .unknown }
        if reader.isEOF {
            switch first {
            case UInt8(ascii: "%"):
                return .percentage
            case UInt8(ascii: "Q"):
                return .q
            default:
                return .unknown
            }
        }
        guard let second = reader.read() else { return .unknown }
        if reader.isEOF {
            switch (first, second) {
            case (UInt8(ascii: "e"), UInt8(ascii: "m")):
                return .ems
            case (UInt8(ascii: "e"), UInt8(ascii: "x")):
                return .exs
            case (UInt8(ascii: "p"), UInt8(ascii: "x")):
                return .pixels
            case (UInt8(ascii: "c"), UInt8(ascii: "m")):
                return .centimeters
            case (UInt8(ascii: "m"), UInt8(ascii: "m")):
                return .millimeters
            case (UInt8(ascii: "i"), UInt8(ascii: "n")):
                return .inches
            case (UInt8(ascii: "p"), UInt8(ascii: "t")):
                return .points
            case (UInt8(ascii: "p"), UInt8(ascii: "c")):
                return .picas
            case (UInt8(ascii: "c"), UInt8(ascii: "h")):
                return .chs
            case (UInt8(ascii: "i"), UInt8(ascii: "c")):
                return .ic
            case (UInt8(ascii: "l"), UInt8(ascii: "h")):
                return .lhs
            case (UInt8(ascii: "v"), UInt8(ascii: "w")):
                return .vw
            case (UInt8(ascii: "v"), UInt8(ascii: "h")):
                return .vh
            case (UInt8(ascii: "v"), UInt8(ascii: "i")):
                return .vi
            case (UInt8(ascii: "v"), UInt8(ascii: "b")):
                return .vb
            default:
                return .unknown
            }
        }
        guard let third = reader.read() else { return .unknown }
        if reader.isEOF {
            switch (first, second, third) {
            case (UInt8(ascii: "r"), UInt8(ascii: "e"), UInt8(ascii: "m")):
                return .rems
            case (UInt8(ascii: "r"), UInt8(ascii: "l"), UInt8(ascii: "h")):
                return .rlhs
            default:
                return .unknown
            }
        }
        guard let fourth = reader.read() else { return .unknown }
        guard reader.isEOF else { return .unknown }
        switch (first, second, third, fourth) {
        case (UInt8(ascii: "v"), UInt8(ascii: "m"), UInt8(ascii: "a"), UInt8(ascii: "x")):
            return .vmax
        case (UInt8(ascii: "v"), UInt8(ascii: "m"), UInt8(ascii: "i"), UInt8(ascii: "n")):
            return .vmin
        default:
            return .unknown
        }
    }
}

extension Double {
    init?(prevalidatedBuffer buffer: BufferView<UInt8>) {
        let value = buffer.withUnsafePointer { nptr, count -> Double? in
            var endPtr: UnsafeMutablePointer<CChar>?
            let decodedValue = strtod_l(nptr, &endPtr, nil)
            if let endPtr, nptr.advanced(by: count) == endPtr {
                return decodedValue
            } else {
                return nil
            }
        }
        guard let value = value else {
            return nil
        }
        self = value
    }
}

extension UInt64 {
    init?(prevalidatedBuffer buffer: BufferView<UInt8>) {
        let value = buffer.withUnsafePointer { nptr, count -> UInt64? in
            var endPtr: UnsafeMutablePointer<CChar>?

            let decodedValue = strtoull_l(nptr, &endPtr, 16, nil)
            if let endPtr, nptr.advanced(by: count) == endPtr {
                return decodedValue
            } else {
                return nil
            }
        }
        guard let value = value else {
            return nil
        }
        self = value
    }
}

private var asciiNumbers: ClosedRange<UInt8> { UInt8(ascii: "0") ... UInt8(ascii: "9") }
