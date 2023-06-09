struct SVGColorScanner {
    var reader: BufferReader
    let opacity: Double

    init(bytes: BufferView<UInt8>, opacity: Double = 1.0) {
        reader = BufferReader(bytes: bytes)
        self.opacity = opacity
    }

    mutating func consumeWhitespaceIfNext(_ ch: UInt8) {
        if let cc = reader.consumeWhitespace(), cc == ch {
            reader.advance()
            _ = reader.consumeWhitespace()
        }
    }

    mutating func scanColorDimension() -> ColorDimension? {
        guard let value = scanNumber() else { return nil }
        if let ch = reader.consumeWhitespace(), ch == UInt8(ascii: "%") {
            reader.advance()
            return .percent(value)
        } else {
            return .absolute(value)
        }
    }

    mutating func scan() -> SVGFill? {
        guard let ascii = reader.consumeWhitespace() else { return nil }
        if ascii == UInt8(ascii: "#") {
            guard let hex = scanHex() else { return nil }
            return .color(color: SVGHexColor(value: hex), opacity: opacity)
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
        case .rgb:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let r = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let g = scanColorDimension() else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: ","))
            guard let b = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return .color(color: SVGRGBColor(r: r, g: g, b: b), opacity: opacity)
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
            return .color(color: SVGRGBAColor(r: r, g: g, b: b, a: a), opacity: opacity)
        case .url:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            consumeWhitespaceIfNext(UInt8(ascii: "#"))
            guard let id = scanIdentity() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return .url(id)
        }
    }

    mutating func scanColor() -> (any SVGUIColor)? {
        guard let ascii = reader.consumeWhitespace() else { return nil }
        if ascii == UInt8(ascii: "#") {
            guard let hex = scanHex() else { return nil }
            return SVGHexColor(value: hex)
        }

        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGFillType(rawValue: name) else {
            return SVGColorName(name: name)
        }
        switch type {
        case .rgb:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            guard let r = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ",")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let g = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ",")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let b = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return SVGRGBColor(r: r, g: g, b: b)
        case .rgba:
            guard consume(ascii: UInt8(ascii: "(")) else { return nil }
            guard let r = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ",")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let g = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ",")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let b = scanColorDimension() else { return nil }
            guard consume(ascii: UInt8(ascii: ",")) else { return nil }
            _ = reader.consumeWhitespace()
            guard let a = scanNumber() else { return nil }
            guard consume(ascii: UInt8(ascii: ")")) else { return nil }
            return SVGRGBAColor(r: r, g: g, b: b, a: a)
        case .url, .inherit, .current:
            return nil
        }
    }

    mutating func scanHex() -> String? {
        guard consume(ascii: UInt8(ascii: "#")) else { return nil }
        let start = reader.readIndex
        reader.skipHex()
        let end = reader.readIndex
        return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
    }

    mutating func scanIdentity() -> String? {
        if reader.isEOF { return nil }
        let start = reader.readIndex
        reader.skipIdentity()
        let end = reader.readIndex
        return String(decoding: reader.bytes[start ..< end], as: UTF8.self)
    }

    mutating func scanNumber() -> Double? {
        if reader.isEOF { return nil }
        let start = reader.readIndex
        reader.skipNumber()
        let end = reader.readIndex
        return Double(prevalidatedBuffer: reader.bytes[start ..< end])
    }

    mutating func consume(ascii: UInt8) -> Bool {
        guard let ch = reader.consumeWhitespace(),
              ch == ascii else { return false }
        reader.advance()
        return true
    }

    static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGColorScanner(bytes: bytes)
            return scanner.scanColor()
        }
    }
}
