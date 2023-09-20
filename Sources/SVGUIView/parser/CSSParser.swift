import CoreGraphics

enum CSSDisplay: String {
    case inline
    case block
    case listItem = "list-item"
    case runIn = "run-in"
    case compact
    case marker
    case table
    case inlineTable = "inline-table"
    case tableRowGroup = "table-row-group"
    case tableHeaderGroup = "table-header-group"
    case tableFooterGroup = "table-hooter-group"
    case tableRow = "table-row"
    case tableColumnGroup = "table-column-group"
    case tableColumn = "table-column"
    case tableCell = "table-cell"
    case tableCaption = "table-caption"
    case none
    case inherit
}

enum CSSVisibility: String {
    case visible
    case hidden
    case collapse
    case inherit
}

struct CSSDeclaration: Equatable, Codable {
    let type: CSSValueType
    let value: CSSValue
}

enum CSSValueType: String, Hashable, Codable {
    case fill
    case height
    case width
    case x
    case y
    case transform
    case fillOpacity = "fill-opacity"
}

enum SVGCSSFillType: String {
    case inherit
    case current = "currentColor"
    case color
    case url
}

enum SVGCSSFill {
    case inherit
    case current
    case color(any SVGUIColor)
    case url(String)
}

enum CSSFuncName: String {
    case rgb
    case rgba
}

extension SVGCSSFill: Equatable {
    static func == (lhs: SVGCSSFill, rhs: SVGCSSFill) -> Bool {
        switch (lhs, rhs) {
        case let (.color(lhs), .color(rhs)):
            return lhs.description == rhs.description
        case let (.url(lhs), .url(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

extension SVGCSSFill: Codable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .inherit:
            try SVGCSSFillType.inherit.rawValue.encode(to: encoder)
        case .current:
            try SVGCSSFillType.current.rawValue.encode(to: encoder)
        case let .color(color):
            var container = encoder.unkeyedContainer()
            try container.encode(SVGCSSFillType.color.rawValue)
            try container.encode(color)
        case let .url(str):
            var container = encoder.unkeyedContainer()
            try container.encode(SVGCSSFillType.url.rawValue)
            try container.encode(str)
        }
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            guard let type = try SVGCSSFillType(rawValue: container.decode(String.self)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
            }
            switch type {
            case .inherit:
                self = .inherit
            case .current:
                self = .current
            default:
                throw CSSParseError.invalid
            }
        } catch {
            var container = try decoder.unkeyedContainer()
            guard let type = try SVGCSSFillType(rawValue: container.decode(String.self)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
            }
            switch type {
            case .color:
                var nestedContainer = try container.nestedUnkeyedContainer()
                guard let colorType = try SVGColorType(rawValue: nestedContainer.decode(String.self)) else {
                    throw CSSParseError.invalid
                }
                switch colorType {
                case .hex:
                    let value = try nestedContainer.decode(String.self)
                    guard let color = SVGHexColor(hex: value) else {
                        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
                    }
                    self = .color(color)
                case .rgb:
                    let r = try nestedContainer.decode(ColorDimension.self)
                    let g = try nestedContainer.decode(ColorDimension.self)
                    let b = try nestedContainer.decode(ColorDimension.self)
                    self = .color(SVGRGBColor(r: r, g: g, b: b))
                case .rgba:
                    let r = try nestedContainer.decode(ColorDimension.self)
                    let g = try nestedContainer.decode(ColorDimension.self)
                    let b = try nestedContainer.decode(ColorDimension.self)
                    let a = try nestedContainer.decode(Double.self)
                    self = .color(SVGRGBAColor(r: r, g: g, b: b, a: a))
                case .named:
                    let name = try nestedContainer.decode(String.self)
                    self = .color(SVGColorName(name: name))
                default:
                    throw CSSParseError.invalid
                }
            case .url:
                self = try .url(container.decode(String.self))
            default:
                throw CSSParseError.invalid
            }
        }
    }
}

enum CSSValue {
    case fill(SVGCSSFill)
    case number(Double)
    case length(SVGLength)
    case transform(CGAffineTransform)
}

extension CSSValue: Equatable {
    static func == (lhs: CSSValue, rhs: CSSValue) -> Bool {
        switch (lhs, rhs) {
        case let (.fill(l), .fill(r)):
            return l == r
        case let (.length(l), .length(r)):
            return l.description == r.description
        case let (.number(l), .number(r)):
            return l == r
        case let (.transform(l), .transform(r)):
            return l == r
        default:
            return false
        }
    }
}

extension CSSValue: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case let .fill(value):
            try value.encode(to: encoder)
        case let .length(value):
            try value.encode(to: encoder)
        case let .transform(value):
            try value.encode(to: encoder)
        case let .number(value):
            try value.encode(to: encoder)
        }
    }
}

extension CSSValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(SVGCSSFill.self) {
            self = .fill(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(CGAffineTransform.self) {
            self = .transform(value)
            return
        }
        if let value = try? container.decode(SVGLength.self) {
            self = .length(value)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
    }
}

enum CSSParseError: String, Error {
    case invalid
}

extension CSSParseError: Codable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if try container.decode(String.self) != "error" {
            throw DecodingError.valueNotFound(String.self, .init(codingPath: decoder.codingPath, debugDescription: "The give data is invalid"))
        }
        guard let value = try CSSParseError(rawValue: container.decode(String.self)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode("error")
        try container.encode(rawValue)
    }
}

struct CSSParser {
    var tokenizer: CSSTopTokenizer
    init(bytes: BufferView<UInt8>) {
        tokenizer = CSSTopTokenizer(bytes: bytes)
    }

    mutating func parse() -> CSSStyle {
        let rules = parseRules()
        return CSSStyle(rules: rules)
    }

    mutating func parseRules() -> [CSSRule] {
        var rules = [CSSRule]()
        while true {
            let token = tokenizer.peek()
            if case .eof = token {
                return rules
            }
            let rule = parseRule()
            rules.append(rule)
        }
    }

    mutating func parseRule() -> CSSRule {
        let selectors = parseSelectors()
        if case .eof = tokenizer.peek() {
            return .qualified(QualifiedCSSRule(selectors: selectors, declarations: [:]))
        }
        var tokenizer = tokenizer.consumeBlock()
        let declarations = parseDeclarations(tokenizer: &tokenizer)
        return .qualified(QualifiedCSSRule(selectors: selectors, declarations: declarations))
    }

    mutating func parseSelectors() -> [CSSSelector] {
        var selectors = [CSSSelector]()
        while true {
            let token = tokenizer.peek()
            if token == .leftBrace || token == .eof {
                return selectors
            }
            switch parseSelector() {
            case let .success(selector):
                selectors.append(selector)
            case .failure:
                break
            }
        }
    }

    mutating func parseSelector() -> Result<CSSSelector, CSSParseError> {
        let token = tokenizer.next()
        switch token {
        case let .delimiter(ch):
            switch ch {
            case UInt8(ascii: "."):
                guard case let .ident(name) = tokenizer.next() else { return .failure(.invalid) }
                return .success(.class(name: name))
            default:
                return .failure(.invalid)
            }
        case let .ident(name: name):
            guard let tag = SVGElementName(rawValue: name) else { return .failure(.invalid) }
            return .success(.type(tag: tag))
        case let .hash(value, isId):
            return isId ? .success(.id(value)) : .failure(.invalid)
        default:
            return .failure(.invalid)
        }
    }

    mutating func parseDeclarations<T>(tokenizer: inout CSSTokenizer<T>) -> [CSSValueType: CSSDeclaration] {
        var declarations = [CSSValueType: CSSDeclaration]()
        while true {
            let token = tokenizer.peek()
            switch token {
            case .eof:
                return declarations
            case .whitespace, .semicolon:
                _ = tokenizer.nextToken()
            case .ident:
                let startIndex = tokenizer.readIndex
                tokenizer.consumeUntilSemicolon()
                var declaration = tokenizer.makeSubTokenizer(startIndex: startIndex, endIndex: tokenizer.readIndex)
                let result = parseDeclaration(tokenizer: &declaration)
                if case let .success(declaration) = result, declarations[declaration.type] == nil {
                    declarations[declaration.type] = declaration
                }
            default:
                break
            }
        }
    }

    mutating func parseDeclarations() -> [CSSValueType: CSSDeclaration] {
        var tokenizer = tokenizer
        return parseDeclarations(tokenizer: &tokenizer)
    }

    mutating func parseDeclaration<T>(tokenizer: inout CSSTokenizer<T>) -> Result<CSSDeclaration, CSSParseError> {
        guard case let .ident(name) = tokenizer.next() else { return .failure(.invalid) }
        guard case .colon = tokenizer.next() else { return .failure(.invalid) }
        guard let type = CSSValueType(rawValue: name) else { return .failure(.invalid) }
        switch type {
        case .fill:
            switch tokenizer.next() {
            case let .ident(name):
                return .success(CSSDeclaration(type: type, value: .fill(.color(SVGColorName(name: name)))))
            case let .hash(value: hash, _):
                guard let color = SVGHexColor(hex: hash) else { return .failure(.invalid) }
                return .success(CSSDeclaration(type: type, value: .fill(.color(color))))
            case let .url(hashId):
                precondition(hashId.hasPrefix("#"))
                let token = tokenizer.next()
                guard case .rightParenthesis = token else { return .failure(.invalid) }
                return .success(CSSDeclaration(type: type, value: .fill(.url(String(hashId.dropFirst())))))
            case let .function(name):
                guard let fname = CSSFuncName(rawValue: name) else { return .failure(.invalid) }
                switch fname {
                case .rgb:
                    guard case let .number(r) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .comma = tokenizer.next() else { return .failure(.invalid) }
                    guard case let .number(g) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .comma = tokenizer.next() else { return .failure(.invalid) }
                    guard case let .number(b) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                    return .success(CSSDeclaration(type: type, value: .fill(.color(SVGRGBColor(r: .absolute(r), g: .absolute(g), b: .absolute(b))))))
                case .rgba:
                    guard case let .number(r) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .comma = tokenizer.next() else { return .failure(.invalid) }
                    guard case let .number(g) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .comma = tokenizer.next() else { return .failure(.invalid) }
                    guard case let .number(b) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .comma = tokenizer.next() else { return .failure(.invalid) }
                    guard case let .number(a) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                    return .success(CSSDeclaration(type: type, value: .fill(.color(SVGRGBAColor(r: .absolute(r), g: .absolute(g), b: .absolute(b), a: a)))))
                }
            default:
                return .failure(.invalid)
            }
        case .fillOpacity:
            switch tokenizer.next() {
            case let .number(value):
                return .success(CSSDeclaration(type: type, value: .number(value)))
            default:
                return .failure(.invalid)
            }
        case .height, .width, .x, .y:
            guard case let .dimension(value, unit) = tokenizer.next() else { return .failure(.invalid) }
            return .success(CSSDeclaration(type: type, value: .length(SVGLength(value: value, unit: unit))))
        case .transform:
            switch parseTransform(tokenizer: &tokenizer) {
            case let .failure(error):
                return .failure(error)
            case let .success(ops):
                var transform: CGAffineTransform = .identity
                for op in ops {
                    op.apply(transform: &transform)
                }
                return .success(CSSDeclaration(type: .transform, value: .transform(transform)))
            }
        }
    }

    mutating func parseTransform() -> Result<[any TransformOperator], CSSParseError> {
        var tokenizer = tokenizer
        return parseTransform(tokenizer: &tokenizer)
    }

    mutating func parseTransform<T>(tokenizer: inout CSSTokenizer<T>) -> Result<[any TransformOperator], CSSParseError> {
        var ops = [any TransformOperator]()
        while true {
            if case .eof = tokenizer.peek() { return .success(ops) }
            guard case let .function(fname) = tokenizer.next() else { return .failure(.invalid) }
            guard let type = TransformType(rawValue: fname) else { return .failure(.invalid) }
            switch type {
            case .scale:
                guard case let .number(x) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                switch tokenizer.next() {
                case let .number(y):
                    let op = ScaleOperator(x: x, y: y)
                    ops.append(op)
                    guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                case .rightParenthesis:
                    let op = ScaleOperator(x: x, y: x)
                    ops.append(op)
                default:
                    return .failure(.invalid)
                }
            case .translate:
                guard case let .number(x) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                switch tokenizer.next() {
                case let .number(y):
                    let op = TranslateOperator(x: x, y: y)
                    ops.append(op)
                    guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                case .rightParenthesis:
                    let op = TranslateOperator(x: x, y: 0)
                    ops.append(op)
                default:
                    return .failure(.invalid)
                }
            case .rotate:
                guard case let .number(angle) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                switch tokenizer.next() {
                case .rightParenthesis:
                    let op = RotateOperator(angle: angle, origin: nil)
                    ops.append(op)
                case let .number(x):
                    if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                    guard case let .number(y) = tokenizer.next() else { return .failure(.invalid) }
                    guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                    let op = RotateOperator(angle: angle, origin: CGPoint(x: x, y: y))
                    ops.append(op)
                default:
                    return .failure(.invalid)
                }
            case .skewX:
                guard case let .number(angle) = tokenizer.next() else { return .failure(.invalid) }
                guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                let op = SkewXOperator(angle: angle)
                ops.append(op)
            case .skewY:
                guard case let .number(angle) = tokenizer.next() else { return .failure(.invalid) }
                guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                let op = SkewYOperator(angle: angle)
                ops.append(op)
            case .matrix:
                guard case let .number(a) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                guard case let .number(b) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                guard case let .number(c) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                guard case let .number(d) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                guard case let .number(tx) = tokenizer.next() else { return .failure(.invalid) }
                if case .comma = tokenizer.peek() { _ = tokenizer.next() }
                guard case let .number(ty) = tokenizer.next() else { return .failure(.invalid) }
                guard case .rightParenthesis = tokenizer.next() else { return .failure(.invalid) }
                let op = MatrixOperator(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
                ops.append(op)
            }
            guard case .function = tokenizer.peek() else {
                break
            }
        }
        return .success(ops)
    }
}
