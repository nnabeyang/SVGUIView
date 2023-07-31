import Foundation

struct BufferReader {
    let bytes: BufferView<UInt8>
    private(set) var readIndex: BufferView<UInt8>.Index
    private let endIndex: BufferView<UInt8>.Index

    private static var whitespaceBitmap: UInt64 {
        1 << UInt8._space | 1 << UInt8._return | 1 << UInt8._newline | 1 << UInt8._tab
    }

    init(bytes: BufferView<UInt8>) {
        self.bytes = bytes
        readIndex = bytes.startIndex
        endIndex = bytes.endIndex
    }

    var isEOF: Bool {
        readIndex == endIndex
    }

    mutating func read() -> UInt8? {
        guard !isEOF else {
            return nil
        }

        defer { bytes.formIndex(after: &readIndex) }

        return bytes[unchecked: readIndex]
    }

    mutating func advance() {
        bytes.formIndex(after: &readIndex)
    }

    func peek(offset: Int = 0) -> UInt8 {
        let peekIndex = bytes.index(readIndex, offsetBy: offset)
        guard peekIndex < endIndex else {
            return 0
        }
        return bytes[unchecked: peekIndex]
    }

    mutating func moveReaderIndex(forwardBy offset: Int) {
        bytes.formIndex(&readIndex, offsetBy: offset)
    }

    func distance(from start: BufferView<UInt8>.Index, to end: BufferView<UInt8>.Index) -> Int {
        bytes.distance(from: start, to: end)
    }

    private mutating func consume(_ string: String) -> Bool {
        let chars = [UInt8](Data(string.utf8))
        for (i, ch) in chars.enumerated() {
            let ascii = peek(offset: i + 1)
            guard ch == ascii else { return false }
        }
        bytes.formIndex(&readIndex, offsetBy: chars.count + 1)
        return true
    }

    mutating func consumeWhitespace() -> UInt8? {
        while readIndex < endIndex {
            let ascii = bytes[unchecked: readIndex]
            if ascii == UInt8(ascii: "&"), consume("#x20;") {
                continue
            }
            if Self.whitespaceBitmap & (1 << ascii) != 0 {
                bytes.formIndex(after: &readIndex)
                continue
            } else {
                return ascii
            }
        }
        return nil
    }

    mutating func skipNumber() {
        guard let ascii = read() else {
            preconditionFailure()
        }
        var allowedSign = false
        var sawDot = false
        switch ascii {
        case UInt8(ascii: "."):
            sawDot = true
        case asciiNumbers, UInt8(ascii: "-"), UInt8(ascii: "+"):
            break
        default:
            preconditionFailure()
        }

        while true {
            let byte = peek()
            guard byte > 0 else { break }
            if _fastPath(asciiNumbers.contains(byte)) {
                moveReaderIndex(forwardBy: 1)
                allowedSign = false
                continue
            }
            switch byte {
            case UInt8(ascii: "."):
                if sawDot {
                    return
                }
                moveReaderIndex(forwardBy: 1)
                allowedSign = false
                sawDot = true
            case UInt8(ascii: "+"), UInt8(ascii: "-"):
                if allowedSign {
                    moveReaderIndex(forwardBy: 1)
                } else {
                    return
                }
                allowedSign = false
            case UInt8(ascii: "e"), UInt8(ascii: "E"):
                moveReaderIndex(forwardBy: 1)
                allowedSign = true
            default:
                if allowedSign {
                    switch peek(offset: -1) {
                    case UInt8(ascii: "e"), UInt8(ascii: "E"):
                        moveReaderIndex(forwardBy: -1)
                    default:
                        break
                    }
                }
                return
            }
        }
    }

    mutating func skipHex() {
        guard let ascii = read() else {
            preconditionFailure()
        }
        switch ascii {
        case asciiNumbers, hexCharsLower, hexCharsUpper:
            break
        default:
            preconditionFailure()
        }

        while true {
            let byte = peek()
            guard byte > 0 else { break }
            switch byte {
            case asciiNumbers, hexCharsLower, hexCharsUpper:
                moveReaderIndex(forwardBy: 1)
                continue
            default:
                return
            }
        }
    }
}

private extension UInt8 {
    static var _space: UInt8 { UInt8(ascii: " ") }
    static var _return: UInt8 { UInt8(ascii: "\r") }
    static var _newline: UInt8 { UInt8(ascii: "\n") }
    static var _tab: UInt8 { UInt8(ascii: "\t") }
}

extension UInt8 {
    var isASCII: Bool {
        (self & ~0x7F) == 0
    }

    var isASCIIAlpha: Bool {
        switch self {
        case allLettersLower, allLettersUpper:
            return true
        default:
            return false
        }
    }

    var isASCIIDigit: Bool {
        switch self {
        case asciiNumbers:
            return true
        default:
            return false
        }
    }

    var isNameStart: Bool {
        isASCIIAlpha || self == UInt8(ascii: "_") || !isASCII
    }

    var isName: Bool {
        isNameStart || isASCIIDigit || self == UInt8(ascii: "-")
    }

    var isNonPrintable: Bool {
        self <= UInt8(ascii: "\u{0008}") ||
            self == UInt8(ascii: "\u{000b}") ||
            (self >= UInt8(ascii: "\u{000e}") && self <= UInt8(ascii: "\u{001f}")) ||
            self == UInt8(ascii: "\u{007f}")
    }

    var isNewLine: Bool {
        self == UInt8(ascii: "\r") || self == UInt8(ascii: "\n") || self == 0x0C // \f
    }
}

private var asciiNumbers: ClosedRange<UInt8> { UInt8(ascii: "0") ... UInt8(ascii: "9") }
private var hexCharsUpper: ClosedRange<UInt8> { UInt8(ascii: "A") ... UInt8(ascii: "F") }
private var hexCharsLower: ClosedRange<UInt8> { UInt8(ascii: "a") ... UInt8(ascii: "f") }
private var allLettersLower: ClosedRange<UInt8> { UInt8(ascii: "a") ... UInt8(ascii: "z") }
private var allLettersUpper: ClosedRange<UInt8> { UInt8(ascii: "A") ... UInt8(ascii: "Z") }
