import CoreGraphics
import Foundation
import _CSSParser
import _SelectorParser

enum CSSDisplay: String, CaseIterable {
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

enum CSSVisibility: String, CaseIterable {
  case visible
  case hidden
  case collapse
  case inherit
}

/// A declaration in a style sheet or the `style` attribute, with what the cascade sorts it by.
struct CSSDeclaration: Comparable {
  let declaration: PropertyDeclaration
  let importance: Importance
  let specificity: Specificity
  var sourceOrder: Int

  var id: PropertyID { declaration.id }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.importance == rhs.importance && lhs.specificity == rhs.specificity && lhs.sourceOrder == rhs.sourceOrder
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    let precA = lhs.cascadePrecedence()
    let precB = rhs.cascadePrecedence()
    if precA != precB {
      return precA < precB
    }
    if lhs.specificity != rhs.specificity {
      return lhs.specificity < rhs.specificity
    }
    return lhs.sourceOrder < rhs.sourceOrder
  }

  private func cascadePrecedence() -> Int {
    switch importance {
    case .normal:
      1
    case .important:
      2
    }
  }
}

enum Importance: Equatable {
  case normal
  case important
}

struct CSSParser {
  private var input: _CSSParser.Parser
  init(input: _CSSParser.Parser) {
    self.input = input
  }

  mutating func parse() -> Stylesheet {
    let rules = parseRules()
    return Stylesheet(rules: rules)
  }

  mutating func parseRules() -> [CSSRule] {
    let bodyParser: RuleBodyParser<CSSParser, CSSRule, StyleParseErrorKind> = RuleBodyParser(input: input, parser: self)
    var rules = [CSSRule]()
    var sourceOrder = 0
    for element in bodyParser {
      if case .success(var rule) = element {
        rule.sourceOrder = sourceOrder
        sourceOrder += 1
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
  typealias Error = StyleParseErrorKind
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
  typealias Prelude = SelectorList<SVGSelectorImpl>
  typealias QualifiedRule = DeclOrRule

  mutating func parseQualifiedBlock(prelude: Prelude, start: ParserState, input: inout _CSSParser.Parser) -> Result<CSSRule, CSSParseError> {
    var declarations = [CSSDeclaration]()
    var parser = CSSDeclarationParser()
    var sourceOrder = 0
    while true {
      let item = next(input: &input, parser: &parser)
      guard let item else { break }
      if case .success(var decl) = item {
        decl.sourceOrder = sourceOrder
        declarations.append(decl)
        sourceOrder += 1
      }
    }
    return .success(CSSRule(selectors: prelude, declarations: declarations, sourceOrder: 0))
  }

  public typealias Element = Result<CSSDeclaration, RuleBodyError<StyleParseErrorKind>>
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
            let result: Result<CSSDeclaration, CSSParseError> = parseUntilAfter(parser: &input, delimiters: .semicolon, errorBehavior: errorBehavior) { input in
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
          let result: Result<CSSDeclaration, CSSParseError>
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

  mutating func parseQualifiedPrelude(input: inout _CSSParser.Parser) -> Result<Prelude, CSSParseError> {
    let selectorParser = SelectorParser(stylesheetOrigin: .author, namespaces: .default(), urlData: .init(URL(string: "https://example.com")!), forSupportsRule: false)
    return SelectorList.parse(parser: selectorParser, input: &input, parseRelative: .no)
  }
}

struct CSSDeclarationParser: DeclarationParser {
  typealias Error = StyleParseErrorKind
  typealias Declaration = CSSDeclaration

  mutating func parseValue(name: String, input: inout _CSSParser.Parser, declarationStart _: inout ParserState) -> Result<CSSDeclaration, CSSParseError> {
    guard let id = PropertyID(rawValue: name.lowercased()) else { return .failure(input.newCustomError(error: .invalid)) }
    let result = input.parseUntilBefore(delimiters: .bang) { input -> Result<PropertyDeclaration, CSSParseError> in
      guard let declaration = Self.declaration(id.property, input: &input) else {
        return .failure(input.newCustomError(error: .invalid))
      }
      return .success(declaration)
    }
    switch result {
    case .success(let declaration):
      let importance: Importance =
        switch input.tryParse(parseImportant(parser:)) {
        case .success:
          .important
        case .failure:
          .normal
        }
      return .success(CSSDeclaration(declaration: declaration, importance: importance, specificity: .default(), sourceOrder: 0))
    case .failure(let error):
      return .failure(error)
    }
  }

  private static func declaration<P: StyleProperty>(_: P.Type, input: inout _CSSParser.Parser) -> PropertyDeclaration? {
    P.declared(css: &input).map { PropertyDeclaration(P.self, $0) }
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
