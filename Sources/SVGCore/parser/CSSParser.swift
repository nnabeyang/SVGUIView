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
}

enum CSSVisibility: String, CaseIterable, Sendable {
  case visible
  case hidden
  case collapse
}

/// The `white-space` property, which decides how the white space in the content of text is drawn.
enum CSSWhiteSpace: String, CaseIterable, Sendable {
  case normal
  case pre
  case nowrap
  case preWrap = "pre-wrap"
  case breakSpaces = "break-spaces"
  case preLine = "pre-line"

  /// Whether a sequence of white space is drawn as one space, and white space at the start and the end of the text
  /// isn't drawn.
  var collapsesSpaces: Bool {
    switch self {
    case .normal, .nowrap, .preLine: true
    case .pre, .preWrap, .breakSpaces: false
    }
  }

  /// Text with its line breaks and tabs turned into spaces, since SVG text doesn't wrap.
  static func spaced(_ text: String) -> String {
    String(
      text.unicodeScalars.map { scalar -> Character in
        switch scalar {
        case "\n", "\r", "\t": " "
        default: Character(scalar)
        }
      })
  }

  /// The characters of text with its white space processed, as SVG draws them on one line.
  ///
  /// Line breaks and tabs become spaces, since SVG text doesn't wrap. Spaces are then collapsed into one, and
  /// removed from the start and the end, unless the value preserves them.
  func processed(_ text: String) -> String {
    let spaced = Self.spaced(text)
    guard collapsesSpaces else { return spaced }
    return spaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
  }
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

/// A rule at the top level of a style sheet.
enum StylesheetRule {
  case style(CSSRule)
  case keyframes(KeyframesRule)
  /// An at-rule that the style sheet ignores, such as `@keyframes` without a block.
  case ignored
}

struct CSSParser {
  private var input: _CSSParser.Parser
  init(input: _CSSParser.Parser) {
    self.input = input
  }

  mutating func parse() -> Stylesheet {
    var rules = [CSSRule]()
    var keyframes = [String: KeyframesRule]()
    for rule in parseRules() {
      switch rule {
      case .style(let rule): rules.append(rule)
      case .keyframes(let rule): keyframes[rule.name] = rule
      case .ignored: break
      }
    }
    return Stylesheet(rules: rules, keyframes: keyframes)
  }

  /// The rules in the order of the style sheet, with the style rules numbered in that order. Invalid rules and
  /// at-rules that the style sheet doesn't support are left out.
  mutating func parseRules() -> [StylesheetRule] {
    let bodyParser: RuleBodyParser<CSSParser, StylesheetRule, StyleParseErrorKind> = RuleBodyParser(
      input: input, parser: self)
    var rules = [StylesheetRule]()
    var sourceOrder = 0
    for element in bodyParser {
      switch element {
      case .success(.style(var rule)):
        rule.sourceOrder = sourceOrder
        sourceOrder += 1
        rules.append(.style(rule))
      case .success(.keyframes(let rule)):
        rules.append(.keyframes(rule))
      case .success(.ignored), .failure:
        break
      }
    }
    return rules
  }
}

extension CSSParser: AtRuleParser {
  typealias AtRule = StylesheetRule

  /// The name of a `@keyframes` rule. Other at-rules are invalid, so that the style sheet drops them.
  mutating func parsePrelude(name: String, input: inout _CSSParser.Parser) -> Result<Prelude, CSSParseError> {
    switch name.lowercased() {
    case "keyframes", "-webkit-keyframes":
      guard let name = keyframesName(&input) else { return .failure(input.newCustomError(error: .invalid)) }
      return .success(.keyframes(name))
    default:
      return .failure(input.newError(kind: .atRuleInvalid(name)))
    }
  }

  mutating func ruleWithoutBlock(prelude _: Prelude, start _: ParserState) -> StylesheetRule {
    .ignored
  }

  mutating func parseBlock(
    prelude: Prelude, start _: ParserState, input: inout _CSSParser.Parser
  ) -> Result<StylesheetRule, CSSParseError> {
    guard case .keyframes(let name) = prelude else { return .failure(input.newCustomError(error: .invalid)) }
    var bodyParser: RuleBodyParser<KeyframeListParser, Keyframe, StyleParseErrorKind> = RuleBodyParser(
      input: input, parser: KeyframeListParser())
    var keyframes = [Keyframe]()
    while let item = bodyParser.next() {
      if case .success(let keyframe) = item { keyframes.append(keyframe) }
    }
    // The block ends where the body parser stopped.
    input = bodyParser.input
    return .success(.keyframes(KeyframesRule(name: name, keyframes: keyframes)))
  }
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
  /// The prelude of a style rule or of an at-rule.
  enum Prelude {
    case selectors(SelectorList<SVGSelectorImpl>)
    /// The name of a `@keyframes` rule.
    case keyframes(String)
  }
  typealias QualifiedRule = DeclOrRule

  mutating func parseQualifiedBlock(
    prelude: Prelude, start _: ParserState, input: inout _CSSParser.Parser
  ) -> Result<StylesheetRule, CSSParseError> {
    guard case .selectors(let selectors) = prelude else { return .failure(input.newCustomError(error: .invalid)) }
    let declarations = CSSDeclarationParser.declarations(in: &input)
    return .success(.style(CSSRule(selectors: selectors, declarations: declarations, sourceOrder: 0)))
  }

  mutating func parseQualifiedPrelude(input: inout _CSSParser.Parser) -> Result<Prelude, CSSParseError> {
    let selectorParser = SelectorParser(stylesheetOrigin: .author, namespaces: .default(), urlData: .init(URL(string: "https://example.com")!), forSupportsRule: false)
    return SelectorList.parse(parser: selectorParser, input: &input, parseRelative: .no).map { .selectors($0) }
  }
}

struct CSSDeclarationParser: DeclarationParser {
  typealias Error = StyleParseErrorKind
  /// The declarations of one declaration in the block: one for a longhand, and one for each of its longhands for a
  /// shorthand.
  typealias Declaration = [CSSDeclaration]

  /// The declarations of a block, such as the block of a style rule or the `style` attribute, numbered in their
  /// order. Invalid declarations are left out.
  static func declarations(in input: inout _CSSParser.Parser) -> [CSSDeclaration] {
    var declarations = [CSSDeclaration]()
    var parser = CSSDeclarationParser()
    while let item = parser.next(input: &input) {
      guard case .success(let items) = item else { continue }
      for var declaration in items {
        declaration.sourceOrder = declarations.count
        declarations.append(declaration)
      }
    }
    return declarations
  }

  mutating func parseValue(name: String, input: inout _CSSParser.Parser, declarationStart _: inout ParserState) -> Result<[CSSDeclaration], CSSParseError> {
    let name = name.lowercased()
    let result = input.parseUntilBefore(delimiters: .bang) { input -> Result<[PropertyDeclaration], CSSParseError> in
      let declarations: [PropertyDeclaration]? =
        if let id = PropertyID(rawValue: name) {
          Self.declaration(id.property, input: &input).map { [$0] }
        } else if name == AnimationShorthand.name {
          AnimationShorthand.declarations(css: &input)
        } else if name == TransitionShorthand.name {
          TransitionShorthand.declarations(css: &input)
        } else {
          nil
        }
      guard let declarations else {
        return .failure(input.newCustomError(error: .invalid))
      }
      return .success(declarations)
    }
    switch result {
    case .success(let declarations):
      let importance: Importance =
        switch input.tryParse(parseImportant(parser:)) {
        case .success:
          .important
        case .failure:
          .normal
        }
      return .success(
        declarations.map {
          CSSDeclaration(declaration: $0, importance: importance, specificity: .default(), sourceOrder: 0)
        })
    case .failure(let error):
      return .failure(error)
    }
  }

  private static func declaration<P: StyleProperty>(_: P.Type, input: inout _CSSParser.Parser) -> PropertyDeclaration? {
    P.declared(css: &input).map { PropertyDeclaration(P.self, $0) }
  }

  typealias Element = Result<[CSSDeclaration], RuleBodyError<StyleParseErrorKind>>
  /// The next declaration of the block, as `RuleBodyParser` reads it.
  private mutating func next(input: inout _CSSParser.Parser) -> Element? {
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
          return parseAtRule(start: start, name: name, input: &input, parser: &self)
        case .ident(let name):
          if parseDeclarations() {
            let parseQualified: Bool = parseQualified()
            let errorBehavior: ParseUntilErrorBehavior = parseQualified ? .stop : .consume
            let result: Result<[CSSDeclaration], CSSParseError> = parseUntilAfter(parser: &input, delimiters: .semicolon, errorBehavior: errorBehavior) { input in
              if case .failure(let error) = input.expectColon() {
                return .failure(.init(basic: error))
              }
              return parseValue(name: name, input: &input, declarationStart: &start)
            }
            if case .failure = result, parseQualified {
              input.reset(state: start)
              if case .success(let qual) = parseQualifiedRule(start: start, input: &input, parser: &self, nested: true) {
                return .success(qual)
              }
            }
            return result.mapError { .init(parseError: $0, message: input.slice(from: start.sourcePosition)) }
          }
        case let token:
          let result: Result<[CSSDeclaration], CSSParseError>
          if parseQualified() {
            input.reset(state: start)
            let nested = parseDeclarations()
            result = parseQualifiedRule(start: start, input: &input, parser: &self, nested: nested)
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
}

extension CSSDeclarationParser: RuleBodyItemParser {
  typealias Prelude = [CSSDeclaration]
  typealias QualifiedRule = [CSSDeclaration]
  typealias AtRule = [CSSDeclaration]

  func parseDeclarations() -> Bool {
    true
  }

  func parseQualified() -> Bool {
    true
  }
}
