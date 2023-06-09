import Foundation

struct SVGPathScanner {
    var reader: BufferReader

    init(bytes: BufferView<UInt8>) {
        reader = BufferReader(bytes: bytes)
    }

    mutating func scan() -> [any PathSegment] {
        var segments = [any PathSegment]()
        while let segment = scanPathSegment() {
            segments.append(segment)
        }
        return segments
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

    mutating func scanBool() -> Bool? {
        guard let ascii = reader.read() else { return nil }
        switch ascii {
        case UInt8(ascii: "0"): return false
        case UInt8(ascii: "1"): return true
        default:
            return nil
        }
    }

    mutating func readSegmentType() -> PathSegmentType? {
        guard let ch = reader.consumeWhitespace(),
              let type = PathSegmentType(rawValue: ch) else { return nil }
        reader.advance()
        return type
    }

    mutating func consumeWhitespaceIfNext(_ ch: UInt8) {
        if let cc = reader.consumeWhitespace(), cc == ch {
            reader.advance()
            _ = reader.consumeWhitespace()
        }
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
