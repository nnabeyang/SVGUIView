import Darwin
import Foundation
import UIKit

struct SVGStrokeScanner {
    var reader: BufferReader

    init(bytes: BufferView<UInt8>) {
        reader = BufferReader(bytes: bytes)
    }

    mutating func scanColorDimension() -> ColorDimension? {
        guard let value = scanNumber() else { return nil }
        if let ch = reader.consumeWhitespace(), ch == UInt8(ascii: "%") {
            return .percent(value)
        } else {
            return .absolute(value)
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

    mutating func scan() -> (any SVGUIColor)? {
        guard let ascii = reader.consumeWhitespace() else { return nil }
        if ascii == UInt8(ascii: "#") {
            guard let hex = scanHex() else { return nil }
            return SVGHexColor(value: hex)
        }

        guard let name = scanIdentity() else {
            return nil
        }
        guard let type = SVGFillType(rawValue: name) else {
            return SVGColorName(name: name.lowercased())
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
        guard reader.peek().isASCIIDigit else { return nil }
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
}
