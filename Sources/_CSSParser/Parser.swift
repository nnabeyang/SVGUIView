struct CachedToken {
  let token: Token
  let startPosition: SourcePosition
  let endState: ParserState
}

public struct ParserInput {
  public var tokenizer: Tokenizer
  var cachedToken: CachedToken?

  public init(input: String) {
    self.tokenizer = Tokenizer(input: input)
    self.cachedToken = nil
  }

  public var cachedTokenRef: Token {
    cachedToken!.token
  }
}

public struct Parser {
  var input: ParserInput
  var atStartOf: BlockType?
  let stopBefore: Delimiters

  public init(input: ParserInput, atStartOf: BlockType?, stopBefore: Delimiters) {
    self.input = input
    self.atStartOf = atStartOf
    self.stopBefore = stopBefore
  }

  public init(input: ParserInput) {
    self.input = input
    self.atStartOf = nil
    self.stopBefore = .none
  }

  public func currentLine() -> String {
    input.tokenizer.currentSourceLine
  }

  mutating public func isExhausted() -> Bool {
    if case .success = expectExhausted() {
      return true
    } else {
      return false
    }
  }

  mutating public func expectExhausted() -> Result<Void, BasicParseError> {
    let start = state
    let result: Result<Void, BasicParseError>
    switch next() {
    case .success(let token):
      result = .failure(start.sourceLocation.newBasicUnexpectedTokenError(token: token))
    case .failure(let error):
      if case .endOfInput = error.kind {
        result = .success(())
      } else {
        fatalError("Unexpected error encountered: \(error)")
      }
    }
    self.reset(state: start)
    return result
  }

  public var position: SourcePosition {
    input.tokenizer.position
  }

  public var currentSourceLocation: SourceLocation {
    input.tokenizer.currentSourceLocation
  }

  public var currentSourceMapUrl: String? {
    input.tokenizer.sourceMapUrl
  }

  public var currentSourceUrl: String? {
    input.tokenizer.sourceUrl
  }

  public func newBasicError(kind: BasicParseErrorKind) -> BasicParseError {
    currentSourceLocation.newBasicError(kind: kind)
  }

  public func newError<E>(kind: BasicParseErrorKind) -> ParseError<E> {
    currentSourceLocation.newError(kind: kind)
  }

  public func newCustomError<E1: Into, E2: From>(error: E1) -> ParseError<E2> where E2.From == E1 {
    currentSourceLocation.newCustomError(error: error)
  }

  public func newCustomError<E>(error: E) -> ParseError<E> {
    currentSourceLocation.newCustomError(error: error)
  }

  public func newBasicUnexpectedTokenError(token: Token) -> BasicParseError {
    newBasicError(kind: .unexpectedToken(token))
  }

  public func newUnexpectedTokenError<E>(token: Token) -> ParseError<E> {
    newError(kind: .unexpectedToken(token))
  }

  mutating public func newErrorForNextToken<E>() -> ParseError<E> {
    switch next() {
    case .success(let token):
      return newError(kind: .unexpectedToken(token))
    case .failure(let error):
      return error.into()
    }
  }

  public var state: ParserState {
    let state = self.input.tokenizer.state
    return ParserState(
      position: state.position,
      currentLineStartPosition: state.currentLineStartPosition,
      currentLineNumber: state.currentLineNumber,
      atStartOf: atStartOf
    )
  }

  mutating public func skipWhitespace() {
    let blockType = atStartOf
    atStartOf = nil
    if let blockType {
      consumeUntilEndOfBlock(blockType: blockType, tokenizer: &input.tokenizer)
    }
    input.tokenizer.skipWhitespace()
  }

  mutating package func skipCdcAndCdo() {
    let blockType = atStartOf
    atStartOf = nil
    if let blockType {
      consumeUntilEndOfBlock(blockType: blockType, tokenizer: &input.tokenizer)
    }
    input.tokenizer.skipCdcAndCdo()
  }

  package func nextByte() -> UInt8? {
    let byte = input.tokenizer.nextByte()
    if stopBefore.contains(.fromByte(byte)) {
      return nil
    }
    return byte
  }

  mutating public func reset(state: ParserState) {
    input.tokenizer.reset(state: state)
    atStartOf = state.atStartOf
  }

  mutating public func lookForVarOrEnvFunctions() {
    input.tokenizer.lookForVarOrEnvFunctions()
  }

  mutating public func seenVarOrEnvFunctions() -> Bool {
    input.tokenizer.seenVarOrEnvFunctions()
  }

  mutating public func tryParse<T, E: Error>(_ thing: (inout Parser) -> Result<T, E>) -> Result<T, E> {
    let start = self.state
    let result = thing(&self)
    if case .failure = result {
      self.reset(state: start)
    }
    return result
  }

  public func slice(range: Range<SourcePosition>) -> String {
    input.tokenizer.slice(range: range)
  }

  public func slice(from startPosition: SourcePosition) -> String {
    input.tokenizer.slice(from: startPosition)
  }

  public mutating func next() -> Result<Token, BasicParseError> {
    skipWhitespace()
    return nextIncludingWhitespaceAndComments()
  }

  mutating public func nextIncludingWhitespace() -> Result<Token, BasicParseError> {
    loop: while true {
      switch nextIncludingWhitespaceAndComments() {
      case .failure(let error):
        return .failure(error)
      case .success(let token):
        if case .comment = token {
          continue
        } else {
          break loop
        }
      }
    }
    return .success(input.cachedTokenRef)
  }

  public mutating func nextIncludingWhitespaceAndComments() -> Result<Token, BasicParseError> {
    let blockType = atStartOf
    atStartOf = nil
    if let blockType {
      consumeUntilEndOfBlock(blockType: blockType, tokenizer: &input.tokenizer)
    }

    let byte = input.tokenizer.nextByte()
    if stopBefore.contains(.fromByte(byte)) {
      return .failure(newBasicError(kind: .endOfInput))
    }
    let tokenStartPosition = input.tokenizer.position
    let usingCachedToken = input.cachedToken.map({ $0.startPosition == tokenStartPosition }) ?? false
    let token: Token
    if usingCachedToken {
      let cachedToken = input.cachedToken!
      input.tokenizer.reset(state: cachedToken.endState)
      if case .function(let name) = cachedToken.token {
        input.tokenizer.seeFunction(name: name)
      }
      token = cachedToken.token
    } else {
      switch input.tokenizer.next() {
      case .failure:
        return .failure(newBasicError(kind: .endOfInput))
      case .success(let newToken):
        input.cachedToken = .init(token: newToken, startPosition: tokenStartPosition, endState: input.tokenizer.state)
      }
      token = input.cachedTokenRef
    }
    if let blockType = BlockType.opening(token: token) {
      atStartOf = blockType
    }
    return .success(token)
  }

  mutating public func parseEntirely<T, E: Error>(parse: (inout Parser) -> Result<T, ParseError<E>>) -> Result<T, ParseError<E>> {
    let result = parse(&self)
    guard case .success = result else { return result }
    if case .failure(let error) = expectExhausted() {
      return .failure(error.into())
    }
    return result
  }

  mutating public func parseCommaSeparated<T, E: Error>(parseOne: (inout Parser) -> Result<T, ParseError<E>>) -> Result<[T], ParseError<E>> {
    parseCommaSeparatedInternal(parseOne: parseOne, ignoreErrors: false)
  }

  mutating public func parseCommaSeparatedIgnoringErrors<T, E: Error>(parseOne: (inout Parser) -> Result<T, ParseError<E>>) -> [T] {
    switch parseCommaSeparatedInternal(parseOne: parseOne, ignoreErrors: true) {
    case .success(let values):
      return values
    case .failure:
      fatalError("unreachable")
    }
  }

  mutating func parseCommaSeparatedInternal<T, E: Error>(parseOne: (inout Parser) -> Result<T, ParseError<E>>, ignoreErrors: Bool) -> Result<[T], ParseError<E>> {
    var values = [T]()
    repeat {
      skipWhitespace()
      switch parseUntilBefore(delimiters: .comma, parse: parseOne) {
      case .success(let v):
        values.append(v)
      case .failure(let e):
        if !ignoreErrors {
          return .failure(e)
        }
      }
      switch next() {
      case .failure: return .success(values)
      case .success(let token):
        if case .comma = token {
          continue
        } else {
          fatalError("unreachable")
        }
      }
    } while true
  }

  mutating public func parseNestedBlock<T, E: Error>(parse: (inout Parser) -> Result<T, ParseError<E>>) -> Result<T, ParseError<E>> {
    _CSSParser.parseNestedBlock(parser: &self, parse: parse)
  }

  mutating public func parseUntilBefore<T, E: Error>(
    delimiters: Delimiters,
    parse: (inout Parser) -> Result<T, ParseError<E>>
  ) -> Result<T, ParseError<E>> {
    _CSSParser.parseUntilBefore(parser: &self, delimiters: delimiters, errorBehavior: .consume, parse: parse)
  }

  mutating public func parseUntilAfter<T, E: Error>(
    delimiters: Delimiters,
    parse: (inout Parser) -> Result<T, ParseError<E>>
  ) -> Result<T, ParseError<E>> {
    _CSSParser.parseUntilAfter(parser: &self, delimiters: delimiters, errorBehavior: .consume, parse: parse)
  }

  mutating public func expectWhitespace() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch nextIncludingWhitespace() {
    case .success(let token):
      if case .whitespace(let value) = token {
        return .success(value)
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectIdent() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .ident(let value) = token {
        return .success(value)
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectIdentMatching(expectedValue: String) -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .ident(let value) = token, value.caseInsensitiveCompare(expectedValue) == .orderedSame {
        return .success(())
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectString() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .quotedString(let value) = token {
        return .success(value)
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectIdentOrString() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .ident(let value), .quotedString(let value):
        return .success(value)
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectUrl() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .unquotedUrl(let value) = token {
        return .success(value)
      } else if case .function(let name) = token, name.caseInsensitiveCompare("url") == .orderedSame {
        let result: Result<String, ParseError<DummyError>> = parseNestedBlock { input in
          input.expectString().mapError({ $0.into() })
        }
        return result.mapError({ $0.basic() })
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectUrlOrString() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .unquotedUrl(let value), .quotedString(let value):
        return .success(value)
      case .function(let name) where name.caseInsensitiveCompare("url") == .orderedSame:
        let result: Result<String, ParseError<DummyError>> = parseNestedBlock { input in
          switch input.expectString() {
          case .success(let value):
            return .success(value)
          case .failure(let error):
            return .failure(error.into())
          }
        }
        switch result {
        case .success(let value):
          return .success(value)
        case .failure(let error):
          return .failure(error.basic())
        }
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectNumber() -> Result<Float32, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .number(let value):
        return .success(value.value)
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectInteger() -> Result<Int32, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .number(let value) = token, let intValue = value.intValue {
        return .success(intValue)
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectPercentage() -> Result<Float32, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .percentage(let value):
        return .success(value.unitValue)
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectColon() -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .colon:
        return .success(())
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectSemicolon() -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .semicolon:
        return .success(())
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectComma() -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .comma:
        return .success(())
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectDelim(expectedValue: Character) -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .delim(let value) = token, value == expectedValue {
        return .success(())
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectCurlyBracketBlock() -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .curlyBracketBlock:
        return .success(())
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectSquareBracketBlock() -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .squareBracketBlock:
        return .success(())
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectParenthesisBlock() -> Result<Void, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .parenthesisBlock:
        return .success(())
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectFunction() -> Result<String, BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      switch token {
      case .function(let name):
        return .success(name)
      default:
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectFunctionMatching(expectedName: String) -> Result<(), BasicParseError> {
    let startLocation = currentSourceLocation
    switch next() {
    case .success(let token):
      if case .function(let name) = token, name.caseInsensitiveCompare(expectedName) == .orderedSame {
        return .success(())
      } else {
        return .failure(startLocation.newBasicUnexpectedTokenError(token: token))
      }
    case .failure(let error):
      return .failure(error)
    }
  }

  mutating public func expectNoErrorToken() -> Result<(), BasicParseError> {
    while true {
      switch nextIncludingWhitespaceAndComments() {
      case .success(let token):
        switch token {
        case .function, .parenthesisBlock, .squareBracketBlock, .curlyBracketBlock:
          let result: Result<Void, ParseError<DummyError>> = parseNestedBlock { input in
            switch input.expectNoErrorToken() {
            case .success:
              return .success(())
            case .failure(let error):
              return .failure(error.into())
            }
          }
          switch result {
          case .success:
            return .success(())
          case .failure(let error):
            return .failure(error.basic())
          }
        default:
          if token.isParseError {
            return .failure(newBasicUnexpectedTokenError(token: token))
          }
        }
      case .failure:
        return .success(())
      }
    }
  }
}

func consumeUntilEndOfBlock(blockType: BlockType, tokenizer: inout Tokenizer) {
  var stack = [BlockType]()
  stack.reserveCapacity(16)
  stack.append(blockType)
  while case .success(let token) = tokenizer.next() {
    if let blockType = BlockType.closing(token: token), stack.last == blockType {
      _ = stack.popLast()
      if stack.isEmpty {
        return
      }
    }
    if let blockType = BlockType.opening(token: token) {
      stack.append(blockType)
    }
  }
}

public struct Delimiters: OptionSet, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let none = Self([])
  // `{`
  public static let curlyBracketBlock = Self(rawValue: 1 << 1)
  // `;`
  public static let semicolon = Self(rawValue: 1 << 2)
  // `!`
  public static let bang = Self(rawValue: 1 << 3)
  // `,`
  public static let comma = Self(rawValue: 1 << 4)

  public static let closeCurlyBracket = Self(rawValue: 1 << 5)
  public static let closeSquareBracket = Self(rawValue: 1 << 6)
  public static let closeParenthesis = Self(rawValue: 1 << 7)

  package static func fromByte(_ byte: UInt8?) -> Self {
    switch byte ?? 0 {
    case UInt8(ascii: ";"): .semicolon
    case UInt8(ascii: "!"): .bang
    case UInt8(ascii: ","): .comma
    case UInt8(ascii: "{"): .curlyBracketBlock
    case UInt8(ascii: "}"): .closeCurlyBracket
    case UInt8(ascii: "]"): .closeSquareBracket
    case UInt8(ascii: ")"): .closeParenthesis
    default: .none
    }
  }

  public func contains(_ member: Delimiters) -> Bool {
    (self.rawValue & member.rawValue) != 0
  }
}

public struct BasicParseError: Error, Equatable {
  public let kind: BasicParseErrorKind
  public let location: SourceLocation
}

extension BasicParseError {
  public func into<E>() -> ParseError<E> {
    ParseError(kind: .basic(kind), location: location)
  }
}

public enum BasicParseErrorKind: Sendable, Equatable {
  case unexpectedToken(Token)
  case endOfInput
  case atRuleInvalid(String)
  case atRuleBodyInvalid
  case qualifiedRuleInvalid
}

extension BasicParseErrorKind: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unexpectedToken(let token):
      "unexpected token: \(token)"
    case .endOfInput:
      "unexpected end of input"
    case .atRuleInvalid(let rule):
      "invalid @ rule encountered: '\(rule)'"
    case .atRuleBodyInvalid:
      "invalid @ rule body encountered"
    case .qualifiedRuleInvalid:
      "invalid qualified rule encountered"
    }
  }
}

public enum ParseErrorKind<CustomType: Equatable & Sendable>: Sendable {
  case basic(BasicParseErrorKind)
  case custom(CustomType)

  public func into<T: From>() -> ParseErrorKind<T> where CustomType: Into, T.From == CustomType {
    switch self {
    case .basic(let basic):
      .basic(basic)
    case .custom(let custom):
      .custom(custom.into())
    }
  }
}

extension ParseErrorKind: Equatable {
  public static func == (lhs: ParseErrorKind<CustomType>, rhs: ParseErrorKind<CustomType>) -> Bool {
    switch (lhs, rhs) {
    case (.basic(let lhs), .basic(let rhs)): lhs == rhs
    case (.custom(let lhs), .custom(let rhs)): lhs == rhs
    default: false
    }
  }
}

public struct ParseError<E: Equatable & Sendable>: Error, Equatable {
  public let kind: ParseErrorKind<E>
  public let location: SourceLocation

  public init(kind: ParseErrorKind<E>, location: SourceLocation) {
    self.kind = kind
    self.location = location
  }

  public init(basic: BasicParseError) {
    self = basic.location.newError(kind: basic.kind)
  }

  public func basic() -> BasicParseError {
    switch kind {
    case .basic(let kind):
      BasicParseError(kind: kind, location: location)
    case .custom:
      fatalError("Not a basic parse error")
    }
  }

  public func into<U: From>() -> ParseError<U> where E: Into, U.From == E {
    ParseError<U>(kind: kind.into(), location: location)
  }
}

public struct DummyError: Equatable, Sendable, Error {}

extension BlockType {
  static func opening(token: Token) -> BlockType? {
    switch token {
    case .function, .parenthesisBlock: .parenthesis
    case .squareBracketBlock: .squareBracket
    case .curlyBracketBlock: .curlyBracket
    default: nil
    }
  }

  static func closing(token: Token) -> BlockType? {
    switch token {
    case .closeParenthesis: .parenthesis
    case .closeSquareBracket: .squareBracket
    case .closeCurlyBracket: .curlyBracket
    default: nil
    }
  }
}

extension SourceLocation {
  func newBasicUnexpectedTokenError(token: Token) -> BasicParseError {
    newBasicError(kind: .unexpectedToken(token))
  }

  func newBasicError(kind: BasicParseErrorKind) -> BasicParseError {
    .init(kind: kind, location: self)
  }

  public func newUnexpectedTokenError<E>(token: Token) -> ParseError<E> {
    newError(kind: .unexpectedToken(token))
  }

  public func newError<E>(kind: BasicParseErrorKind) -> ParseError<E> {
    .init(kind: .basic(kind), location: self)
  }

  public func newCustomError<E1: Into, E2: From>(error: E1) -> ParseError<E2> where E2.From == E1 {
    .init(kind: .custom(error.into()), location: self)
  }

  public func newCustomError<E>(error: E) -> ParseError<E> {
    .init(kind: .custom(error), location: self)
  }
}

public func parseUntilBefore<T, E: Error>(
  parser: inout Parser,
  delimiters: Delimiters,
  errorBehavior: ParseUntilErrorBehavior,
  parse: (inout Parser) -> Result<T, ParseError<E>>
) -> Result<T, ParseError<E>> {
  let delimiters: Delimiters = [parser.stopBefore, delimiters]
  let result: Result<T, ParseError<E>>
  do {
    let atStartOf = parser.atStartOf
    parser.atStartOf = nil
    var delimitedParser = Parser(
      input: parser.input,
      atStartOf: atStartOf,
      stopBefore: delimiters
    )
    result = delimitedParser.parseEntirely(parse: parse)
    if case .stop = errorBehavior, case .failure = result {
      return result
    }
    if let blockType = delimitedParser.atStartOf {
      consumeUntilEndOfBlock(blockType: blockType, tokenizer: &delimitedParser.input.tokenizer)
    }
  }
  while true {
    if delimiters.contains(.fromByte(parser.input.tokenizer.nextByte())) {
      break
    }
    if case .success(let token) = parser.input.tokenizer.next() {
      if let blockType = BlockType.opening(token: token) {
        consumeUntilEndOfBlock(blockType: blockType, tokenizer: &parser.input.tokenizer)
      }
    } else {
      break
    }
  }
  return result
}

public func parseUntilAfter<T, E: Error>(
  parser: inout Parser,
  delimiters: Delimiters,
  errorBehavior: ParseUntilErrorBehavior,
  parse: (inout Parser) -> Result<T, ParseError<E>>
) -> Result<T, ParseError<E>> {
  let result = parseUntilBefore(parser: &parser, delimiters: delimiters, errorBehavior: errorBehavior, parse: parse)
  if case .stop = errorBehavior, case .failure = result {
    return result
  }
  let nextByte = parser.input.tokenizer.nextByte()
  if let nextByte, !parser.stopBefore.contains(.fromByte(nextByte)) {
    assert(delimiters.contains(.fromByte(nextByte)))
    parser.input.tokenizer.advance(1)
    if nextByte == UInt8(ascii: "{") {
      consumeUntilEndOfBlock(blockType: .curlyBracket, tokenizer: &parser.input.tokenizer)
    }
  }
  return result
}

public func parseNestedBlock<T, E: Error>(
  parser: inout Parser,
  parse: (inout Parser) -> Result<T, ParseError<E>>
) -> Result<T, ParseError<E>> {
  let blockType = parser.atStartOf
  parser.atStartOf = nil
  guard let blockType else {
    fatalError(
      """
      A nested parser can only be created when a function,
      curlyBracket, squareBracket, or parenthesis
      token was just consumed.
      """)
  }
  let closingDelimiter: Delimiters =
    switch blockType {
    case .curlyBracket: .closeCurlyBracket
    case .squareBracket: .closeSquareBracket
    case .parenthesis: .closeParenthesis
    }
  let result: Result<T, ParseError<E>>
  do {
    var nestedParser = Parser(
      input: parser.input,
      atStartOf: nil,
      stopBefore: closingDelimiter
    )
    result = nestedParser.parseEntirely(parse: parse)
    if let blockType = nestedParser.atStartOf {
      consumeUntilEndOfBlock(blockType: blockType, tokenizer: &nestedParser.input.tokenizer)
    }
  }
  consumeUntilEndOfBlock(blockType: blockType, tokenizer: &parser.input.tokenizer)
  return result
}

public func parseImportant(parser: inout Parser) -> Result<Void, BasicParseError> {
  let result = parser.expectDelim(expectedValue: "!")
  guard case .success = result else {
    return result
  }
  return parser.expectIdentMatching(expectedValue: "important")
}
