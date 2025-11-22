import CoreGraphics
import _CSSParser

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
  case clipPath = "clip-path"
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
    case (.color(let lhs), .color(let rhs)):
      return lhs.description == rhs.description
    case (.url(let lhs), .url(let rhs)):
      return lhs == rhs
    default:
      return false
    }
  }
}

extension SVGCSSFill: Codable {
  func encode(to encoder: any Encoder) throws {
    switch self {
    case .inherit:
      try SVGCSSFillType.inherit.rawValue.encode(to: encoder)
    case .current:
      try SVGCSSFillType.current.rawValue.encode(to: encoder)
    case .color(let color):
      var container = encoder.unkeyedContainer()
      try container.encode(SVGCSSFillType.color.rawValue)
      try container.encode(color)
    case .url(let str):
      var container = encoder.unkeyedContainer()
      try container.encode(SVGCSSFillType.url.rawValue)
      try container.encode(str)
    }
  }

  init(from decoder: any Decoder) throws {
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
  case clipPath(SVGClipPath)
}

extension CSSValue: Equatable {
  static func == (lhs: CSSValue, rhs: CSSValue) -> Bool {
    switch (lhs, rhs) {
    case (.fill(let l), .fill(let r)):
      return l == r
    case (.length(let l), .length(let r)):
      return l.description == r.description
    case (.number(let l), .number(let r)):
      return l == r
    case (.transform(let l), .transform(let r)):
      return l == r
    default:
      return false
    }
  }
}

extension CSSValue: Encodable {
  func encode(to encoder: any Encoder) throws {
    switch self {
    case .fill(let value):
      try value.encode(to: encoder)
    case .length(let value):
      try value.encode(to: encoder)
    case .transform(let value):
      try value.encode(to: encoder)
    case .number(let value):
      try value.encode(to: encoder)
    case .clipPath:
      try "clip-path".encode(to: encoder)
    }
  }
}

extension CSSValue: Decodable {
  init(from decoder: any Decoder) throws {
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

struct CSSParser {
  private var input: _CSSParser.Parser
  init(input: _CSSParser.Parser) {
    self.input = input
  }

  mutating func parse() -> CSSStyle {
    let rules = parseRules()
    return CSSStyle(rules: rules)
  }

  mutating func parseRules() -> [CSSRule] {
    let bodyParser: RuleBodyParser<CSSParser, CSSRule, CSSParseError> = RuleBodyParser(input: input, parser: self)
    var rules = [CSSRule]()
    for element in bodyParser {
      if case .success(let rule) = element {
        rules.append(rule)
      }
    }
    return rules
  }
}

extension CSSParser: AtRuleParser {
  typealias AtRule = CSSRule
}

extension CSSParser: DeclarationParser {
  typealias Error = CSSParseError
  typealias Declaration = DeclOrRule
}

extension CSSParser: RuleBodyItemParser {
  func parseDeclarations() -> Bool {
    true
  }

  func parseQualified() -> Bool {
    true
  }
}

extension CSSParser: QualifiedRuleParser {
  typealias Prelude = [CSSSelector]
  typealias QualifiedRule = DeclOrRule

  mutating func parseQualifiedBlock(prelude: Prelude, start: _CSSParser.ParserState, input: inout _CSSParser.Parser) -> Result<CSSRule, _CSSParser.ParseError<CSSParseError>> {
    var declarations = [CSSValueType: CSSDeclaration]()
    var parser = CSSDeclarationParser()
    while true {
      let item = next(input: &input, parser: &parser)
      guard let item else { break }
      if case .success(let decl) = item {
        if declarations[decl.type] == nil {
          declarations[decl.type] = decl
        }
      }
    }
    return .success(.qualified(.init(selectors: prelude, declarations: declarations)))
  }

  public typealias Element = Result<CSSDeclaration, RuleBodyError<CSSParseError>>
  public mutating func next(input: inout _CSSParser.Parser, parser: inout CSSDeclarationParser) -> Element? {
    while true {
      input.skipWhitespace()
      var start = input.state
      switch input.nextIncludingWhitespaceAndComments() {
      case .failure:
        return nil
      case .success(let token):
        switch token {
        case .closeCurlyBracket, .whitespace, .semicolon, .comment: continue
        case .atKeyword(let name):
          return parseAtRule(start: start, name: name, input: &input, parser: &parser)
        case .ident(let name):
          if parser.parseDeclarations() {
            let parseQualified: Bool = parser.parseQualified()
            let errorBehavior: ParseUntilErrorBehavior = parseQualified ? .stop : .consume
            let result: Result<CSSDeclaration, _CSSParser.ParseError<CSSParseError>> = parseUntilAfter(parser: &input, delimiters: .semicolon, errorBehavior: errorBehavior) { input in
              if case .failure(let error) = input.expectColon() {
                return .failure(.init(basic: error))
              }
              return parser.parseValue(name: name, input: &input, declarationStart: &start)
            }
            if case .failure = result, parseQualified {
              input.reset(state: start)
              if case .success(let qual) = parseQualifiedRule(start: start, input: &input, parser: &parser, nested: true) {
                return .success(qual)
              }
            }
            return result.mapError { .init(parseError: $0, message: input.slice(from: start.sourcePosition)) }
          }
        case let token:
          let result: Result<CSSDeclaration, _CSSParser.ParseError<CSSParseError>>
          if parser.parseQualified() {
            input.reset(state: start)
            let nested = parser.parseDeclarations()
            result = parseQualifiedRule(start: start, input: &input, parser: &parser, nested: nested)
          } else {
            result = input.parseUntilAfter(delimiters: .semicolon) { _ in
              .failure(start.sourceLocation.newUnexpectedTokenError(token: token))
            }
          }
          switch result {
          case .success(let r):
            return .success(r)
          case .failure(let error):
            return .failure(.init(parseError: error, message: input.slice(from: start.sourcePosition)))
          }
        }
      }
    }
  }

  mutating func parseQualifiedPrelude(input: inout _CSSParser.Parser) -> Result<Prelude, _CSSParser.ParseError<Self.Error>> {
    var selectors = [CSSSelector]()
    while case .success(let token) = input.nextIncludingWhitespace() {
      switch token {
      case .delim(let ch):
        switch ch {
        case ".":
          guard case .success(let name) = input.expectIdent() else { return .failure(input.newCustomError(error: .invalid)) }
          selectors.append(.class(name: name))
        default:
          return .failure(input.newCustomError(error: .invalid))
        }
      case .ident(let name):
        guard let tag = SVGElementName(rawValue: name) else { return .failure(input.newCustomError(error: .invalid)) }
        selectors.append(.type(tag: tag))
      case .idHash(let value):
        selectors.append(.id(value))
      default:
        break
      }
    }
    return .success(selectors)
  }
}

struct CSSDeclarationParser: DeclarationParser {
  typealias Error = CSSParseError
  typealias Declaration = CSSDeclaration

  mutating func parseValue(name: String, input: inout _CSSParser.Parser, declarationStart: inout _CSSParser.ParserState) -> Result<CSSDeclaration, _CSSParser.ParseError<CSSParseError>> {
    guard let type = CSSValueType(rawValue: name) else { return .failure(input.newCustomError(error: .invalid)) }
    switch type {
    case .fill:
      switch input.next() {
      case .success(let token):
        switch token {
        case .ident(let color):
          return .success(CSSDeclaration(type: type, value: .fill(.color(SVGColorName(name: color)))))
        case .idHash(let hash), .hash(let hash):
          guard let color = SVGHexColor(hex: hash) else { return .failure(input.newCustomError(error: .invalid)) }
          return .success(CSSDeclaration(type: type, value: .fill(.color(color))))
        case .unquotedUrl(let url):
          guard url.hasPrefix("#") else {
            return .failure(input.newCustomError(error: .invalid))
          }
          return .success(CSSDeclaration(type: type, value: .fill(.url(String(url.dropFirst())))))
        case .function(let name):
          guard let fname = CSSFuncName(rawValue: name) else { return .failure(input.newCustomError(error: .invalid)) }
          switch fname {
          case .rgb:
            switch SVGRGBColor.parse(context: .init(), input: &input) {
            case .success(let color):
              return .success(CSSDeclaration(type: type, value: .fill(.color(color))))
            case .failure:
              return .failure(input.newCustomError(error: .invalid))
            }
          case .rgba:
            switch SVGRGBAColor.parse(context: .init(), input: &input) {
            case .success(let color):
              return .success(CSSDeclaration(type: type, value: .fill(.color(color))))
            case .failure:
              return .failure(input.newCustomError(error: .invalid))
            }
          }
        default:
          return .failure(input.newCustomError(error: .invalid))
        }
      case .failure(let error):
        return .failure(.init(basic: error))
      }
    case .fillOpacity:
      switch input.next() {
      case .success(let token):
        switch token {
        case .number(let value):
          return .success(CSSDeclaration(type: type, value: .number(Double(value.value))))
        default:
          return .failure(input.newCustomError(error: .invalid))
        }
      case .failure(let error):
        return .failure(.init(basic: error))
      }
    case .height, .width, .x, .y:
      switch input.next() {
      case .success(let token):
        switch token {
        case .number(let value):
          return .success(CSSDeclaration(type: type, value: .length(SVGLength(value: Double(value.value), unit: .number))))
        case .dimention(let value):
          return .success(CSSDeclaration(type: type, value: .length(SVGLength(value: Double(value.value), unit: .init(value.unit)))))
        default:
          return .failure(input.newCustomError(error: .invalid))
        }
      case .failure(let error):
        return .failure(.init(basic: error))
      }
    case .transform:
      switch CGAffineTransform.parse(context: .init(), input: &input) {
      case .success(let transform):
        return .success(CSSDeclaration(type: .transform, value: .transform(transform)))
      case .failure:
        return .failure(input.newCustomError(error: .invalid))
      }
    case .clipPath:
      switch input.next() {
      case .success(let token):
        switch token {
        case .unquotedUrl(let url):
          guard url.hasPrefix("#") else {
            return .failure(input.newCustomError(error: .invalid))
          }
          return .success(CSSDeclaration(type: .clipPath, value: .clipPath(.url(url: String(url.dropFirst())))))
        default:
          return .failure(input.newCustomError(error: .invalid))
        }
      case .failure(let error):
        return .failure(.init(basic: error))
      }
    }
  }
}

extension CSSDeclarationParser: RuleBodyItemParser {
  typealias Prelude = CSSDeclaration
  typealias QualifiedRule = CSSDeclaration
  typealias AtRule = CSSDeclaration

  func parseDeclarations() -> Bool {
    true
  }

  func parseQualified() -> Bool {
    true
  }
}
