import Foundation

enum CSSUnitType: UInt8 {
    case unknown = 0
    case number = 1
    case percentage = 2
    case ems = 3
    case exs = 4
    case px = 5
    case cm = 6
    case mm = 7
    case `in` = 8
    case pt = 9
    case pc = 10
    case deg = 11
    case rad = 12
    case grad = 13
    case ms = 14
    case s = 15
    case hz = 16
    case khz = 17
    case dimension = 18
    case string = 19
    case uri = 20
    case indent = 21
    case attr = 22
    case counter = 23
    case rect = 24
    case rgbcolor = 25
    case chs = 26
    case ic = 27
    case rems = 28
    case lhs = 29
    case rlhs = 30

    init(_ string: String) {
        switch string {
        case "hz":
            self = .hz
        case "cm":
            self = .cm
        case "px":
            self = .px
        case "em":
            self = .ems
        case "ex":
            self = .exs
        case "mm":
            self = .mm
        case "ch":
            self = .chs
        case "ic":
            self = .ic
        case "rem":
            self = .rems
        case "lh":
            self = .lhs
        case "rlh":
            self = .rlhs
        default:
            self = .px
        }
    }
}

enum HashTokenType {
    case id
    case unrestricted
}

enum BlockType: Int {
    case notBlock = 0
    case blockStart = 1
    case blockEnd = 2
}

enum CSSTokenName: String, Codable {
    case ident
    case function
    case atKeyword = "at-keyword"
    case hash
    case url
    case badUrl = "bad-url"
    case number
    case dimension
    case includeMatch = "~="
    case dashMatch = "|="
    case prefixMatch = "^="
    case suffixMatch = "$="
    case substringMatch = "*="
    case column = "||"
    case whitespace = " "
    case CDO = "<!--"
    case CDC = "-->"
    case colon = ":"
    case semicolon = ";"
    case comma = ","
    case leftParenthesis = "("
    case rightParenthesis = ")"
    case leftBracket = "["
    case rightBracket = "]"
    case leftBrace = "{"
    case rightBrace = "}"
    case string
    case badString = "bad-string"
    case eof
    case comment
}

enum CSSToken: Equatable {
    case ident(name: String)
    case function(name: String)
    case atKeyword(name: String)
    case hash(value: String, isId: Bool)
    case url(String)
    case badUrl
    case delimiter(UInt8)
    case number(Double)
    case dimension(value: Double, unit: CSSUnitType)
    case includeMatch
    case dashMatch
    case prefixMatch
    case suffixMatch
    case substringMatch
    case column
    case whitespace
    case CDO
    case CDC
    case colon
    case semicolon
    case comma
    case leftParenthesis
    case rightParenthesis
    case leftBracket
    case rightBracket
    case leftBrace
    case rightBrace
    case string(String)
    case badString
    case eof
    case comment

    var type: String {
        if case let .delimiter(ch) = self {
            return String(decoding: [ch], as: UTF8.self)
        }
        let name: CSSTokenName = {
            switch self {
            case .ident:
                return .ident
            case .function:
                return .function
            case .atKeyword:
                return .atKeyword
            case .hash:
                return .hash
            case .url:
                return .url
            case .badUrl:
                return .badUrl
            case .delimiter:
                fatalError()
            case .number:
                return .number
            case .dimension:
                return .dimension
            case .includeMatch:
                return .includeMatch
            case .dashMatch:
                return .dashMatch
            case .prefixMatch:
                return .prefixMatch
            case .suffixMatch:
                return .suffixMatch
            case .substringMatch:
                return .substringMatch
            case .column:
                return .column
            case .whitespace:
                return .whitespace
            case .CDO:
                return .CDO
            case .CDC:
                return .CDC
            case .colon:
                return .colon
            case .semicolon:
                return .semicolon
            case .comma:
                return .comma
            case .leftParenthesis:
                return .leftParenthesis
            case .rightParenthesis:
                return .rightParenthesis
            case .leftBracket:
                return .leftBracket
            case .rightBracket:
                return .rightBracket
            case .leftBrace:
                return .leftBrace
            case .rightBrace:
                return .rightBrace
            case .string:
                return .string
            case .badString:
                return .badString
            case .eof:
                return .eof
            case .comment:
                return .comment
            }
        }()
        return name.rawValue
    }

    var blockType: BlockType {
        switch self {
        case .leftBrace, .leftBracket, .leftParenthesis, .url, .function:
            return .blockStart
        case .rightBrace, .rightBracket, .rightParenthesis:
            return .blockEnd
        default:
            return .notBlock
        }
    }
}

extension CSSToken: Codable {
    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let tokenName = CSSTokenName(rawValue: value) else {
                let a: UInt8 = Data(value.utf8)[0]
                self = .delimiter(a)
                return
            }
            switch tokenName {
            case .includeMatch:
                self = .includeMatch
            case .dashMatch:
                self = .dashMatch
            case .prefixMatch:
                self = .prefixMatch
            case .suffixMatch:
                self = .suffixMatch
            case .substringMatch:
                self = .substringMatch
            case .column:
                self = .column
            case .whitespace:
                self = .whitespace
            case .CDO:
                self = .CDO
            case .CDC:
                self = .CDC
            case .colon:
                self = .colon
            case .semicolon:
                self = .semicolon
            case .comma:
                self = .comma
            case .leftParenthesis:
                self = .leftParenthesis
            case .rightParenthesis:
                self = .rightParenthesis
            case .leftBracket:
                self = .leftBracket
            case .rightBracket:
                self = .rightBracket
            case .leftBrace:
                self = .leftBrace
            case .rightBrace:
                self = .rightBrace
            case .badString:
                self = .badString
            case .eof:
                self = .eof
            case .comment:
                self = .comment
            default:
                fatalError()
            }
        } catch {
            var container = try decoder.unkeyedContainer()
            let value = try container.decode(String.self)
            guard let tokenName = CSSTokenName(rawValue: value) else {
                fatalError()
            }
            switch tokenName {
            case .ident:
                let string = try container.decode(String.self)
                self = .ident(name: string)
                return
            case .function:
                let string = try container.decode(String.self)
                self = .function(name: string)
            case .atKeyword:
                let name = try container.decode(String.self)
                self = .atKeyword(name: name)
            case .hash:
                let value = try container.decode(String.self)
                let isId = try container.decode(Bool.self)
                self = .hash(value: value, isId: isId)
            case .url:
                let value = try container.decode(String.self)
                self = .url(value)
            case .number:
                let value = try container.decode(Double.self)
                self = .number(value)
            case .string:
                let string = try container.decode(String.self)
                self = .string(string)
            default:
                fatalError()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .ident(name):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(name)
        case let .function(name):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(name)
        case let .atKeyword(value):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(value)
        case let .hash(value, isId):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(value)
            try container.encode(isId)
        case let .url(value):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(value)
        case let .number(value):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(value)
        case let .string(string):
            var container = encoder.unkeyedContainer()
            try container.encode(type)
            try container.encode(string)
        default:
            try type.encode(to: encoder)
        }
    }
}
