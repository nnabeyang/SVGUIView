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

/// A baseline of the font of text, which `dominant-baseline` and `alignment-baseline` align the text by.
enum TextBaseline: Sendable {
  case alphabetic
  case ideographic
  case hanging
  case mathematical
  case central
  case middle
  case textBeforeEdge
  case textAfterEdge
}

/// `dominant-baseline`, the baseline that text and the tspans in it align by.
enum DominantBaseline: String, CaseIterable, Sendable {
  case auto
  case useScript = "use-script"
  case noChange = "no-change"
  case resetSize = "reset-size"
  case alphabetic
  case ideographic
  case hanging
  case mathematical
  case central
  case middle
  case textAfterEdge = "text-after-edge"
  case textBeforeEdge = "text-before-edge"

  /// The baseline. SVG 2 doesn't have `use-script` of SVG 1.1, which picks a baseline by the script, and is the
  /// alphabetic baseline like `auto`. `no-change` and `reset-size` compute to the value of the parent.
  var baseline: TextBaseline {
    switch self {
    case .auto, .useScript, .noChange, .resetSize, .alphabetic: .alphabetic
    case .ideographic: .ideographic
    case .hanging: .hanging
    case .mathematical: .mathematical
    case .central: .central
    case .middle: .middle
    case .textAfterEdge: .textAfterEdge
    case .textBeforeEdge: .textBeforeEdge
    }
  }
}

/// `alignment-baseline`, the baseline that a tspan aligns by instead of the dominant baseline.
enum AlignmentBaseline: String, CaseIterable, Sendable {
  case auto
  case baseline
  case beforeEdge = "before-edge"
  case textBeforeEdge = "text-before-edge"
  case middle
  case central
  case afterEdge = "after-edge"
  case textAfterEdge = "text-after-edge"
  case ideographic
  case alphabetic
  case hanging
  case mathematical

  /// The baseline, or `nil` for the dominant baseline.
  var baseline: TextBaseline? {
    switch self {
    case .auto, .baseline: nil
    case .beforeEdge, .textBeforeEdge: .textBeforeEdge
    case .middle: .middle
    case .central: .central
    case .afterEdge, .textAfterEdge: .textAfterEdge
    case .ideographic: .ideographic
    case .alphabetic: .alphabetic
    case .hanging: .hanging
    case .mathematical: .mathematical
    }
  }
}

/// `baseline-shift`, how far a tspan moves up from the baseline of its parent.
enum BaselineShift: Equatable, Sendable {
  case baseline
  case sub
  case `super`
  /// A length, or a percentage of the size of the font.
  case length(SVGLength)
}

/// The lines of `text-decoration`.
struct TextDecorationLines: OptionSet, Hashable, Sendable {
  let rawValue: UInt8

  static let underline = Self(rawValue: 1 << 0)
  static let overline = Self(rawValue: 1 << 1)
  static let lineThrough = Self(rawValue: 1 << 2)

  init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// The lines of a value, which is `none` or keywords of lines separated by white space, each at most once, or
  /// `nil` if it isn't valid.
  init?(_ text: String, caseInsensitive: Bool) {
    let keywords = text.split(whereSeparator: \.isWhitespace).map { caseInsensitive ? $0.lowercased() : String($0) }
    if keywords == ["none"] {
      self = []
      return
    }
    var lines: Self = []
    for keyword in keywords {
      let line: Self
      switch keyword {
      case "underline": line = .underline
      case "overline": line = .overline
      case "line-through": line = .lineThrough
      default: return nil
      }
      guard !lines.contains(line) else { return nil }
      lines.insert(line)
    }
    guard !lines.isEmpty else { return nil }
    self = lines
  }
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

  var name: PropertyDeclaration.Name { declaration.name }

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
  /// An `@import` rule before the other rules, which reads a style sheet in another file.
  case `import`(ExternalStyleSheet)
  /// An `@font-face` rule, which reads a font.
  case fontFace(FontFaceRule)
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
      case .import, .fontFace, .ignored: break
      }
    }
    return Stylesheet(rules: rules, keyframes: keyframes)
  }

  /// The rules in the order of the style sheet, with the style rules numbered in that order. Invalid rules and
  /// at-rules that the style sheet doesn't support are left out, and so are `@import` rules after other rules, as
  /// CSS Cascade 4 says.
  mutating func parseRules() -> [StylesheetRule] {
    let bodyParser: RuleBodyParser<CSSParser, StylesheetRule, StyleParseErrorKind> = RuleBodyParser(
      input: input, parser: self)
    var rules = [StylesheetRule]()
    var sourceOrder = 0
    var importsAllowed = true
    for element in bodyParser {
      switch element {
      case .success(.style(var rule)):
        rule.sourceOrder = sourceOrder
        sourceOrder += 1
        rules.append(.style(rule))
        importsAllowed = false
      case .success(.keyframes(let rule)):
        rules.append(.keyframes(rule))
        importsAllowed = false
      case .success(.import(let sheet)):
        if importsAllowed { rules.append(.import(sheet)) }
      case .success(.fontFace(let rule)):
        rules.append(.fontFace(rule))
        importsAllowed = false
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
    case "font-face":
      // The prelude has nothing.
      guard input.isExhausted() else { return .failure(input.newCustomError(error: .invalid)) }
      return .success(.fontFace)
    case "import":
      // The URL, and the media queries after it, which the rest of the prelude is.
      guard case .success(let url) = input.expectUrlOrString() else {
        return .failure(input.newCustomError(error: .invalid))
      }
      let start = input.position
      while case .success = input.next() {}
      let media = input.slice(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
      return .success(.import(ExternalStyleSheet(href: url, media: media.isEmpty ? nil : media)))
    default:
      return .failure(input.newError(kind: .atRuleInvalid(name)))
    }
  }

  mutating func ruleWithoutBlock(prelude: Prelude, start _: ParserState) -> StylesheetRule {
    if case .import(let sheet) = prelude { .import(sheet) } else { .ignored }
  }

  mutating func parseBlock(
    prelude: Prelude, start _: ParserState, input: inout _CSSParser.Parser
  ) -> Result<StylesheetRule, CSSParseError> {
    if case .fontFace = prelude {
      guard let rule = FontFaceRule(descriptors: FontFaceDescriptorParser.descriptors(in: &input)) else {
        return .failure(input.newCustomError(error: .invalid))
      }
      return .success(.fontFace(rule))
    }
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
    /// The style sheet that an `@import` rule reads.
    case `import`(ExternalStyleSheet)
    /// An `@font-face` rule, whose descriptors are in its block.
    case fontFace
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
    // The names of custom properties are case-sensitive.
    let name = name.hasPrefix("--") ? name : name.lowercased()
    let result = input.parseUntilBefore(delimiters: .bang) { input -> Result<[PropertyDeclaration], CSSParseError> in
      if name.hasPrefix("--") {
        return Self.customDeclaration(name, input: &input).map { .success([$0]) }
          ?? .failure(input.newCustomError(error: .invalid))
      }
      // The value is parsed first as a value without `var()`, which most values are, and the tokenizer notes any
      // `var()` that it reads.
      let start = input.state
      input.lookForVarOrEnvFunctions()
      let declarations = Self.propertyDeclarations(name, input: &input)
      // A value that isn't valid can have `var()` after the tokens that the parser read.
      if input.seenVarOrEnvFunctions() || declarations == nil {
        input.reset(state: start)
        return Self.unparsedDeclarations(name, input: &input).map { .success($0) }
          ?? .failure(input.newCustomError(error: .invalid))
      }
      return .success(declarations ?? [])
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

  /// The declarations of a property or of the longhands of a shorthand, by its name in lowercase, or `nil` if the
  /// name is unknown or the value is invalid.
  static func propertyDeclarations(_ name: String, input: inout _CSSParser.Parser) -> [PropertyDeclaration]? {
    if let id = PropertyID(rawValue: name) {
      Self.declaration(id.property, input: &input).map { [$0] }
    } else if name == AnimationShorthand.name {
      AnimationShorthand.declarations(css: &input)
    } else if name == TransitionShorthand.name {
      TransitionShorthand.declarations(css: &input)
    } else if name == MarkerShorthand.name {
      MarkerShorthand.declarations(css: &input)
    } else {
      nil
    }
  }

  private static func declaration<P: StyleProperty>(_: P.Type, input: inout _CSSParser.Parser) -> PropertyDeclaration? {
    P.declared(css: &input).map { PropertyDeclaration(P.self, $0) }
  }

  /// The declaration of a custom property, whose value is its text without the whitespace around it, or `nil` if
  /// the value isn't valid, such as one with unbalanced brackets. CSS Variables 1 keeps the value as tokens until it's
  /// substituted, and the keywords that every property takes keep their meanings.
  static func customDeclaration(_ name: String, input: inout _CSSParser.Parser) -> PropertyDeclaration? {
    let start = input.state
    while true {
      switch input.next() {
      case .success(.badString), .success(.badUrl), .success(.closeParenthesis), .success(.closeSquareBracket),
        .success(.closeCurlyBracket):
        return nil
      case .success:
        continue
      case .failure:
        break
      }
      break
    }
    let text = input.slice(from: start.sourcePosition).trimmingCharacters(in: .whitespacesAndNewlines)
    let value: Declared<String> =
      switch keyword(removingComments(from: text)) {
      case "inherit": .inherit
      case "initial": .initial
      case "unset", "revert", "revert-layer": .unset
      default: .value(text)
      }
    return PropertyDeclaration(custom: name, value)
  }

  /// The declarations of a property or a shorthand whose value has `var()`, which keep the text of the value to parse
  /// once the custom properties are substituted, or `nil` if the value has no `var()` or the property is unknown.
  static func unparsedDeclarations(_ name: String, input: inout _CSSParser.Parser) -> [PropertyDeclaration]? {
    let start = input.state
    input.lookForVarOrEnvFunctions()
    var isBalanced = true
    while true {
      switch input.next() {
      case .success(.badString), .success(.badUrl), .success(.closeParenthesis), .success(.closeSquareBracket),
        .success(.closeCurlyBracket):
        isBalanced = false
        continue
      case .success:
        continue
      case .failure:
        break
      }
      break
    }
    let hasVariables = input.seenVarOrEnvFunctions()
    let text = input.slice(from: start.sourcePosition).trimmingCharacters(in: .whitespacesAndNewlines)
    guard hasVariables, isBalanced, containsVariable(text) else {
      input.reset(state: start)
      return nil
    }
    let longhands: [any StyleProperty.Type]
    let shorthand: String?
    if let id = PropertyID(rawValue: name) {
      longhands = [id.property]
      shorthand = nil
    } else if let shorthandLonghands = Self.longhands(ofShorthand: name) {
      longhands = shorthandLonghands
      shorthand = name
    } else {
      input.reset(state: start)
      return nil
    }
    let value = UnparsedValue(text: text, shorthand: shorthand)
    return longhands.map { PropertyDeclaration($0.id, unparsed: value) }
  }

  /// The longhands of a shorthand, or `nil` if the name isn't a shorthand.
  static func longhands(ofShorthand name: String) -> [any StyleProperty.Type]? {
    switch name {
    case AnimationShorthand.name: AnimationShorthand.longhands
    case TransitionShorthand.name: TransitionShorthand.longhands
    case MarkerShorthand.name: MarkerShorthand.longhands
    default: nil
    }
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
