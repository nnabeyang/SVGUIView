struct CSSTokenizer<C: Collection<CSSToken>> {
    private let tokens: C
    private(set) var readIndex: C.Index
    private let endIndex: C.Index

    private init(tokens: C) {
        self.tokens = tokens
        readIndex = tokens.startIndex
        endIndex = tokens.endIndex
    }

    init(bytes: BufferView<UInt8>) {
        var scanner = CSSScanner(bytes: bytes)
        var tokens = [CSSToken]()
        while true {
            let token = scanner.scan()
            if case .eof = token {
                break
            }
            tokens.append(token)
        }
        self.init(tokens: tokens as! C)
    }

    func makeSubTokenizer(startIndex: C.Index, endIndex: C.Index) -> CSSTokenizer<ArraySlice<CSSToken>> {
        CSSTokenizer<ArraySlice<CSSToken>>(tokens: tokens[startIndex ..< endIndex] as! ArraySlice<CSSToken>)
    }

    @discardableResult
    mutating func consumeComponentValue() -> Bool {
        var nestingLeval = 0
        while true {
            let token = next()
            if case .blockStart = token.blockType {
                nestingLeval += 1
            }
            if case .blockEnd = token.blockType {
                nestingLeval -= 1
            }
            guard nestingLeval > 0, token != .eof else {
                break
            }
        }
        return nestingLeval == 0
    }

    mutating func consumeBlock() -> CSSTokenizer<ArraySlice<CSSToken>> {
        let startIndex = tokens.index(readIndex, offsetBy: 1)
        let closed = consumeComponentValue()
        guard closed else {
            return makeSubTokenizer(startIndex: startIndex, endIndex: readIndex)
        }
        return makeSubTokenizer(startIndex: startIndex, endIndex: tokens.index(readIndex, offsetBy: -1))
    }

    mutating func consumeUntilSemicolon() {
        while true {
            let token = peek()
            guard token != .eof, token != .semicolon else { break }
            consumeComponentValue()
        }
    }

    mutating func peek(offset: Int = 0) -> CSSToken {
        let peekIndex = tokens.index(readIndex, offsetBy: offset)
        guard peekIndex < endIndex else {
            return .eof
        }
        return tokens[peekIndex]
    }

    mutating func next() -> CSSToken {
        while true {
            guard readIndex < endIndex else {
                return .eof
            }
            let token = nextToken()
            switch token {
            case .whitespace, .comment:
                continue
            default:
                return token
            }
        }
    }

    mutating func nextToken() -> C.Element {
        guard readIndex < endIndex else {
            return .eof
        }
        let token = tokens[readIndex]
        readIndex = tokens.index(readIndex, offsetBy: 1)
        return token
    }
}

typealias CSSTopTokenizer = CSSTokenizer<[CSSToken]>

struct CSSScanner {
    private var reader: BufferReader

    init(bytes: BufferView<UInt8>) {
        reader = BufferReader(bytes: bytes)
    }

    private static var whitespaceBitmap: UInt64 {
        1 << UInt8._space | 1 << UInt8._return | 1 << UInt8._newline | 1 << UInt8._tab
    }

    mutating func scan() -> CSSToken {
        while true {
            let token = nextToken()
            switch token {
            case .whitespace, .comment:
                continue
            default:
                return token
            }
        }
    }

    mutating func nextToken() -> CSSToken {
        let ch = reader.peek()
        guard ch > 0 else {
            return .eof
        }

        guard ch.isASCII else {
            return consumeIdentLikeToken()
        }
        switch ch {
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return consumeString(ch: ch)
        case UInt8(ascii: "$"):
            return consumeDollarSign(ch: ch)
        case UInt8(ascii: "#"):
            return consumeHash(ch: ch)
        case UInt8(ascii: "("):
            reader.advance()
            return .leftParenthesis
        case UInt8(ascii: ")"):
            reader.advance()
            return .rightParenthesis
        case UInt8(ascii: "*"):
            return consumeAsterisk(ch: ch)
        case UInt8(ascii: "+"), UInt8(ascii: "."):
            return consumePlusOrFullStop(ch: ch)
        case UInt8(ascii: ","):
            reader.advance()
            return .comma
        case UInt8(ascii: "-"):
            return consumeHyphenMinus(ch: ch)
        case UInt8(ascii: "/"):
            return consumeSolidus(ch: ch)
        case UInt8(ascii: ":"):
            reader.advance()
            return .colon
        case UInt8(ascii: ";"):
            reader.advance()
            return .semicolon
        case UInt8(ascii: "<"):
            return consumeLessThan(ch: ch)
        case UInt8(ascii: "@"):
            return commercialAt(ch: ch)
        case UInt8(ascii: "["):
            reader.advance()
            return .leftBracket
        case UInt8(ascii: "]"):
            reader.advance()
            return .rightBracket
        case UInt8(ascii: "^"):
            return consumeFlexAccent(ch: ch)
        case UInt8(ascii: "{"):
            reader.advance()
            return .leftBrace
        case UInt8(ascii: "|"):
            return consumeVerticalLine(ch: ch)
        case UInt8(ascii: "}"):
            reader.advance()
            return .rightBrace
        case UInt8(ascii: "~"):
            return consumeTilde(ch: ch)
        case ._space, ._return, ._newline, ._tab:
            return consumeWhitespace()
        case asciiNumbers:
            return consumeNumericToken(ch: ch)
        default:
            if ch.isName {
                return consumeIdentLikeToken()
            } else {
                reader.advance()
                return .delimiter(ch)
            }
        }
    }

    mutating func blockStart(name: String) -> CSSToken {
        .function(name: name)
    }

    mutating func consumeWhitespace() -> CSSToken {
        _ = reader.consumeWhitespace()
        return .whitespace
    }

    mutating func consumeSolidus(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "/"))
        reader.advance()
        if consumeIfNext(UInt8(ascii: "*")) {
            consumeComment()
            return .comment
        }
        return .delimiter(ch)
    }

    mutating func consumeHash(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "#"))
        reader.advance()
        let first = reader.peek()
        if first.isName || Self.twoCharsAreValidEscape(first: first, second: reader.peek(offset: 1)) {
            let isId = nextCharsAreIdentifier()
            return .hash(value: consumeName(), isId: isId)
        }
        return .delimiter(ch)
    }

    mutating func consumePlusOrFullStop(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "+") || ch == UInt8(ascii: "."))
        guard ch > 0 else { return .eof }
        if nextCharsAreNumber(ch: ch) {
            return consumeNumericToken(ch: ch)
        }
        reader.advance()
        return .delimiter(UInt8(ascii: "."))
    }

    mutating func consumeNumericToken(ch: UInt8) -> CSSToken {
        let value = numericNumber(ch: ch)
        if nextCharsAreIdentifier() {
            return .dimension(value: value, unit: .init(consumeName()))
        } else if consumeIfNext(UInt8(ascii: "%")) {
            return .dimension(value: value, unit: .percentage)
        }
        return .number(value)
    }

    private func nextCharsAreIdentifier() -> Bool {
        nextCharsAreIdentifier(reader.peek())
    }

    func nextCharsAreIdentifier(_ first: UInt8) -> Bool {
        let second = reader.peek(offset: 1)
        if first.isNameStart || Self.twoCharsAreValidEscape(first: first, second: second) {
            return true
        }
        if first == UInt8(ascii: "-") {
            return second.isNameStart || second == UInt8(ascii: "-") || nextTwoCharsAreValidEscape(offset: 0)
        }
        return false
    }

    private func nextCharsAreNumber(ch first: UInt8) -> Bool {
        if first.isASCIIDigit {
            return true
        }
        let second = reader.peek(offset: 1)
        switch first {
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            return second.isASCIIDigit || second == UInt8(ascii: ".") && reader.peek(offset: 2).isASCIIDigit
        case UInt8(ascii: "."):
            return second.isASCIIDigit
        default:
            return false
        }
    }

    static func twoCharsAreValidEscape(first: UInt8, second: UInt8) -> Bool {
        first == UInt8(ascii: "\\") && !second.isNewLine
    }

    func nextTwoCharsAreValidEscape(offset: Int) -> Bool {
        let first = reader.peek(offset: offset + 1)
        let second = reader.peek(offset: offset + 2)
        return Self.twoCharsAreValidEscape(first: first, second: second)
    }

    mutating func numericNumber(ch: UInt8) -> Double {
        precondition(asciiNumbers ~= ch || ch == UInt8(ascii: "+") || ch == UInt8(ascii: "-") || ch == UInt8(ascii: "."))
        let start = reader.readIndex
        reader.skipNumber()
        let end = reader.readIndex
        guard let value = Double(prevalidatedBuffer: reader.bytes[start ..< end]) else {
            fatalError()
        }
        return value
    }

    mutating func consumeIdentLikeToken() -> CSSToken {
        let name = consumeName()
        if consumeIfNext(UInt8(ascii: "(")) {
            if name == "url" {
                return consumeURL()
            }
            return blockStart(name: name)
        }
        return .ident(name: name)
    }

    mutating func consumeIfNext(_ ch: UInt8) -> Bool {
        guard reader.peek() == ch else { return false }
        reader.advance()
        return true
    }

    mutating func whiteSpace(_: UInt8) -> CSSToken {
        _ = reader.consumeWhitespace()
        return .whitespace
    }

    mutating func consumeComment() {
        while let ch = reader.read() {
            if ch != UInt8(ascii: "*") {
                continue
            }
            guard let next = reader.read() else { return }
            if next == UInt8(ascii: "/") {
                return
            }
        }
    }

    mutating func consumeString(ch endingCode: UInt8) -> CSSToken {
        precondition(endingCode == UInt8(ascii: "\"") || endingCode == UInt8(ascii: "'"))
        reader.advance()
        var size = 0
        while true {
            let c = reader.peek(offset: size)
            guard c != UInt8(ascii: "\\") else {
                break
            }
            if c == endingCode {
                let start = reader.readIndex
                reader.moveReaderIndex(forwardBy: size + 1)
                let end = reader.readIndex.advanced(by: -1)
                let string = String(decoding: reader.bytes[start ..< end], as: UTF8.self)
                return .string(string)
            }
            if c.isNewLine {
                reader.moveReaderIndex(forwardBy: size)
                return .badString
            }
            size += 1
        }
        return .badString
    }

    mutating func consumeFlexAccent(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "^"))
        reader.advance()
        if consumeIfNext(UInt8(ascii: "=")) {
            return .prefixMatch
        }
        return .delimiter(ch)
    }

    mutating func consumeDollarSign(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "$"))
        reader.advance()
        if consumeIfNext(UInt8(ascii: "=")) {
            return .suffixMatch
        }
        return .delimiter(ch)
    }

    mutating func consumeVerticalLine(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "|"))
        reader.advance()
        if consumeIfNext(UInt8(ascii: "=")) {
            return .dashMatch
        }
        if consumeIfNext(UInt8(ascii: "|")) {
            return .column
        }
        return .delimiter(ch)
    }

    mutating func consumeLessThan(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "<"))
        reader.advance()
        if reader.peek(offset: 0) == UInt8(ascii: "!"),
           reader.peek(offset: 1) == UInt8(ascii: "-"),
           reader.peek(offset: 2) == UInt8(ascii: "-")
        {
            reader.moveReaderIndex(forwardBy: 3)
            return .CDO
        }
        return .delimiter(ch)
    }

    mutating func consumeHyphenMinus(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "-"))
        if nextCharsAreNumber(ch: ch) {
            return consumeNumericToken(ch: ch)
        }
        if reader.peek(offset: 1) == UInt8(ascii: "-"),
           reader.peek(offset: 2) == UInt8(ascii: ">")
        {
            reader.moveReaderIndex(forwardBy: 3)
            return .CDC
        }
        if nextCharsAreIdentifier(ch) {
            return consumeIdentLikeToken()
        }
        reader.advance()
        return .delimiter(ch)
    }

    mutating func consumeTilde(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "~"))
        reader.advance()
        if consumeIfNext(UInt8(ascii: "=")) {
            return .includeMatch
        }
        return .delimiter(ch)
    }

    mutating func consumeAsterisk(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "*"))
        reader.advance()
        if consumeIfNext(UInt8(ascii: "=")) {
            return .substringMatch
        }
        return .delimiter(ch)
    }

    mutating func commercialAt(ch: UInt8) -> CSSToken {
        precondition(ch == UInt8(ascii: "@"))
        reader.advance()
        if nextCharsAreIdentifier() {
            return .atKeyword(name: consumeName())
        }
        return .delimiter(ch)
    }

    mutating func consumeURL() -> CSSToken {
        _ = reader.consumeWhitespace()
        var size = 0
        while true {
            let c = reader.peek(offset: size)
            if c == UInt8(ascii: ")") {
                let start = reader.readIndex
                reader.moveReaderIndex(forwardBy: size)
                let end = reader.readIndex
                let url = String(decoding: reader.bytes[start ..< end], as: UTF8.self)
                return .url(url)
            } else if c <= UInt8(ascii: " ") ||
                c == UInt8(ascii: "\\") ||
                c == UInt8(ascii: "\"") ||
                c == UInt8(ascii: "\'") ||
                c == UInt8(ascii: "(") ||
                c == UInt8(ascii: "\u{007f}")
            {
                reader.advance()
                break
            }
            size += 1
        }
        let start = reader.readIndex
        while true {
            guard let c = reader.read(), c != UInt8(ascii: ")") else {
                let end = reader.readIndex
                let url = String(decoding: reader.bytes[start ..< end], as: UTF8.self)
                return .url(url)
            }
            if Self.whitespaceBitmap & (1 << c) != 0 {
                guard let ch = reader.consumeWhitespace(), ch != UInt8(ascii: ")") else {
                    let end = reader.readIndex.advanced(by: -1)
                    let url = String(decoding: reader.bytes[start ..< end], as: UTF8.self)
                    return .url(url)
                }
                return .badUrl
            }

            if c == UInt8(ascii: "\"") || c == UInt8(ascii: "\'") || c == UInt8(ascii: "(") || c.isNonPrintable {
                let end = reader.readIndex.advanced(by: -1)
                let url = String(decoding: reader.bytes[start ..< end], as: UTF8.self)
                return .url(url)
            }
        }
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
                let end = reader.readIndex // .readIndex.advanced(by: 1)
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
        fatalError()
    }
}

private extension UInt8 {
    static var _space: UInt8 { UInt8(ascii: " ") }
    static var _return: UInt8 { UInt8(ascii: "\r") }
    static var _newline: UInt8 { UInt8(ascii: "\n") }
    static var _tab: UInt8 { UInt8(ascii: "\t") }
}

private var asciiNumbers: ClosedRange<UInt8> { UInt8(ascii: "0") ... UInt8(ascii: "9") }
