public protocol DeclarationParser {
  associatedtype Declaration
  associatedtype Error: Swift.Error & Equatable & Sendable

  mutating func parseValue(name: String, input: inout Parser, declarationStart: inout ParserState) -> Result<Declaration, ParseError<Error>>
}

extension DeclarationParser {
  public mutating func parseValue(name: String, input: inout Parser, declarationStart _: inout ParserState) -> Result<Declaration, ParseError<Error>> {
    .failure(input.newError(kind: .unexpectedToken(.ident(name))))
  }
}

public protocol AtRuleParser {
  associatedtype Prelude
  associatedtype AtRule
  associatedtype Error: Swift.Error & Equatable & Sendable

  mutating func parsePrelude(name: String, input: inout Parser) -> Result<Prelude, ParseError<Self.Error>>

  mutating func ruleWithoutBlock(prelude: Prelude, start: ParserState) -> AtRule

  mutating func parseBlock(prelude: Prelude, start: ParserState, input: inout Parser) -> Result<AtRule, ParseError<Self.Error>>
}

extension AtRuleParser {
  public mutating func parsePrelude(name: String, input: inout Parser) -> Result<Prelude, ParseError<Self.Error>> {
    .failure(input.newError(kind: .atRuleInvalid(name)))
  }

  public mutating func ruleWithoutBlock(prelude _: Prelude, start _: ParserState) -> AtRule {
    fatalError("not implemented")
  }

  public mutating func parseBlock(prelude _: Prelude, start _: ParserState, input: inout Parser) -> Result<AtRule, ParseError<Self.Error>> {
    .failure(input.newError(kind: .atRuleBodyInvalid))
  }
}

public protocol QualifiedRuleParser {
  associatedtype Prelude
  associatedtype QualifiedRule
  associatedtype Error: Swift.Error & Equatable & Sendable

  mutating func parseQualifiedPrelude(input: inout Parser) -> Result<Prelude, ParseError<Self.Error>>

  mutating func parseQualifiedBlock(prelude: Prelude, start: ParserState, input: inout Parser) -> Result<QualifiedRule, ParseError<Self.Error>>
}

extension QualifiedRuleParser {
  public mutating func parseQualifiedPrelude(input: inout Parser) -> Result<Prelude, ParseError<Self.Error>> {
    .failure(input.newError(kind: .qualifiedRuleInvalid))
  }
  public mutating func parseQualifiedBlock(prelude _: Prelude, start _: ParserState, input: inout Parser) -> Result<QualifiedRule, ParseError<Self.Error>> {
    .failure(input.newError(kind: .qualifiedRuleInvalid))
  }
}

public struct RuleBodyParser<P, I, E> where E: Swift.Error & Equatable & Sendable {
  public typealias Item = I
  public typealias Error = E

  public var input: Parser
  public var parser: P

  public init(input: Parser, parser: P) {
    self.input = input
    self.parser = parser
  }
}

public struct RuleBodyError<E: Swift.Error & Equatable & Sendable>: Error {
  public let parseError: ParseError<E>
  public let message: String
  public init(parseError: ParseError<E>, message: String) {
    self.parseError = parseError
    self.message = message
  }
  public var description: String { "" }
}

public protocol RuleBodyItemParser: DeclarationParser, QualifiedRuleParser, AtRuleParser
where DeclOrRule == QualifiedRule, DeclOrRule == AtRule {
  associatedtype DeclOrRule = Declaration
  func parseDeclarations() -> Bool
  func parseQualified() -> Bool
}

extension RuleBodyParser: IteratorProtocol, Sequence where P: RuleBodyItemParser, P.DeclOrRule == I, P.Declaration == I, P.Error == E {
  public typealias Element = Result<I, RuleBodyError<E>>
  /// https://drafts.csswg.org/css-syntax/#consume-a-blocks-contents
  public mutating func next() -> Element? {
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
            let result: Result<I, ParseError<E>> = parseUntilAfter(parser: &input, delimiters: .semicolon, errorBehavior: errorBehavior) { input in
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
          let result: Result<I, ParseError<E>>
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
}

public struct StyleSheetParser<P> {
  public var input: Parser
  public var parser: P
  public var anyRuleSoFar: Bool

  private init(input: Parser, parser: P, anyRuleSoFar: Bool) {
    self.input = input
    self.parser = parser
    self.anyRuleSoFar = anyRuleSoFar
  }
}

extension StyleSheetParser where P: QualifiedRuleParser & AtRuleParser {
  public init<R, E>(input: Parser, parser: inout P) where P.QualifiedRule == R, P.AtRule == R, P.Error == E {
    self.input = input
    self.parser = parser
    self.anyRuleSoFar = false
  }
}

extension StyleSheetParser: IteratorProtocol, Sequence where P: QualifiedRuleParser & AtRuleParser, P.AtRule == P.QualifiedRule {
  public typealias Element = Result<P.QualifiedRule /* | P.AtRule */, RuleBodyError<P.Error>>
  mutating public func next() -> Element? {
    while true {
      input.skipCdcAndCdo()
      let start = input.state
      let atKeyword: String?
      switch input.nextByte() {
      case .none:
        return nil
      case .some(UInt8(ascii: "@")):
        switch input.nextIncludingWhitespaceAndComments() {
        case .success(.atKeyword(let name)):
          atKeyword = name
        default:
          input.reset(state: start)
          atKeyword = nil
        }
      default:
        atKeyword = nil
      }
      if let atKeyword {
        let firstStyleSheetRule = !anyRuleSoFar
        anyRuleSoFar = true
        if firstStyleSheetRule && atKeyword.caseInsensitiveCompare("charset") == .orderedSame {
          let _: Result<Void, ParseError<DummyError>> = input.parseUntilAfter(delimiters: [.semicolon, .curlyBracketBlock]) { _ in .success(()) }
        } else {
          return parseAtRule(start: start, name: atKeyword, input: &input, parser: &parser)
        }
      } else {
        anyRuleSoFar = true
        let result = parseQualifiedRule(start: start, input: &input, parser: &parser, nested: false)
        return result.mapError { .init(parseError: $0, message: input.slice(from: start.sourcePosition)) }
      }

    }
    return nil
  }
}

public func parseOneDeclaration<P, E>(input: inout Parser, parser: inout P) -> Result<P.Declaration, RuleBodyError<E>>
where P: DeclarationParser, P.Error == E {
  let start = input.state
  let startPosition = input.position
  let result: Result<P.Declaration, ParseError<E>> = input.parseEntirely { input in
    switch input.expectIdent() {
    case .success(let name):
      if case .failure(let error) = input.expectColon() {
        return .failure(.init(basic: error))
      }
      var start = start
      return parser.parseValue(name: name, input: &input, declarationStart: &start)
    case .failure(let error):
      return .failure(.init(basic: error))
    }
  }
  switch result {
  case .success(let value):
    return .success(value)
  case .failure(let error):
    return .failure(.init(parseError: error, message: input.slice(from: startPosition)))
  }
}

public func parseOneRule<R, P, E>(input: inout Parser, parser: inout P) -> Result<R, ParseError<E>>
where P: QualifiedRuleParser & AtRuleParser, P.QualifiedRule == R, P.AtRule == R, P.Error == E {
  input.parseEntirely(parse: { input in
    input.skipWhitespace()
    let start = input.state
    let atKeyword: String?
    if UInt8(ascii: "@") == input.nextByte() {
      switch input.nextIncludingWhitespaceAndComments() {
      case .success(.atKeyword(let name)):
        atKeyword = name
      case .failure(let error):
        return .failure(.init(basic: error))
      default:
        atKeyword = nil
      }
    } else {
      atKeyword = nil
    }
    if let name = atKeyword {
      let result = parseAtRule(start: start, name: name, input: &input, parser: &parser)
      switch result {
      case .success(let value):
        return .success(value)
      case .failure(let error):
        return .failure(error.parseError)
      }
    } else {
      let result = parseQualifiedRule(start: start, input: &input, parser: &parser, nested: false)
      switch result {
      case .success(let value):
        return .success(value)
      case .failure(let error):
        return .failure(error)
      }
    }
  })
}

public func parseAtRule<P, E>(start: ParserState, name: String, input: inout Parser, parser: inout P) -> Result<P.AtRule, RuleBodyError<E>>
where P: AtRuleParser, P.Error == E {
  let delmiters: Delimiters = [.semicolon, .curlyBracketBlock]
  let result = input.parseUntilBefore(delimiters: delmiters) { input in
    return parser.parsePrelude(name: name, input: &input)
  }
  switch result {
  case .success(let prelude):
    let result: Result<P.AtRule, ParseError<E>>
    switch input.next() {
    case .success(.semicolon), .failure:
      result = .success(parser.ruleWithoutBlock(prelude: prelude, start: start))
    case .success(.curlyBracketBlock):
      result = parseNestedBlock(parser: &input) { input in
        return parser.parseBlock(prelude: prelude, start: start, input: &input)
      }
    default:
      fatalError("unreachable")
    }
    switch result {
    case .success(let rule):
      return .success(rule)
    case .failure:
      return .failure(.init(parseError: input.newUnexpectedTokenError(token: .semicolon), message: input.slice(from: start.sourcePosition)))
    }
  case .failure(let error):
    let endPosition = input.position
    switch input.next() {
    case .success(.curlyBracketBlock), .success(.semicolon), .failure: break
    default: fatalError("unreachable")
    }
    return .failure(.init(parseError: error, message: input.slice(range: start.sourcePosition..<endPosition)))
  }
}

func looksLikeACustomProperty(input: inout Parser) -> Bool {
  let ident = input.expectIdent()
  guard case .success(let i) = ident, i.hasPrefix("--") else { return false }
  if case .success = input.expectColon() {
    return true
  } else {
    return false
  }
}

// https://drafts.csswg.org/css-syntax/#consume-a-qualified-rule
public func parseQualifiedRule<P, E>(start: ParserState, input: inout Parser, parser: inout P, nested: Bool) -> Result<P.QualifiedRule, ParseError<E>>
where P: QualifiedRuleParser, P.Error == E {
  input.skipWhitespace()
  let state = input.state
  if looksLikeACustomProperty(input: &input) {
    let delmiters: Delimiters = nested ? .semicolon : .curlyBracketBlock
    let _: Result<Void, ParseError<DummyError>> = input.parseUntilAfter(delimiters: delmiters) { _ in .success(()) }
    return .failure(state.sourceLocation.newError(kind: .qualifiedRuleInvalid))
  }
  let delmiters: Delimiters =
    if nested {
      [.semicolon, .curlyBracketBlock]
    } else {
      .curlyBracketBlock
    }
  input.reset(state: state)
  let prelude: Result<P.Prelude, ParseError<E>> = input.parseUntilBefore(delimiters: delmiters) { input in
    parser.parseQualifiedPrelude(input: &input)
  }
  if case .failure(let error) = input.expectCurlyBracketBlock() {
    return .failure(.init(basic: error))
  }
  switch prelude {
  case .success(let prelude):
    return parseNestedBlock(parser: &input) { parser.parseQualifiedBlock(prelude: prelude, start: start, input: &$0) }
  case .failure(let error):
    return .failure(error)
  }
}
