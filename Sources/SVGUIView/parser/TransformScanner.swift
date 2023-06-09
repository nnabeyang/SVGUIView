import CoreGraphics

struct TransformScanner {
    var reader: BufferReader

    init(bytes: BufferView<UInt8>) {
        reader = BufferReader(bytes: bytes)
    }

    mutating func scan() -> [any TransformOperator] {
        var ops = [any TransformOperator]()
        while let op = scanTransform() {
            ops.append(op)
        }
        return ops
    }

    mutating func scanNumber() -> Double? {
        if reader.isEOF { return nil }
        let start = reader.readIndex
        reader.skipNumber()
        let end = reader.readIndex
        return Double(prevalidatedBuffer: reader.bytes[start ..< end])
    }

    mutating func scanIdentity() -> String? {
        if reader.isEOF { return nil }
        let start = reader.readIndex
        reader.skipIdentity()
        let end = reader.readIndex
        return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
    }

    mutating func consume(ascii: UInt8) -> Bool {
        guard let ch = reader.consumeWhitespace(),
              ch == ascii else { return false }
        reader.advance()
        return true
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

    mutating func scanTransform() -> (any TransformOperator)? {
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
