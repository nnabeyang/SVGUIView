import Foundation

enum SeenStatus: Equatable {
  case dontCare
  case lookingForThem
  case seenAtLeastOne
}

enum CSSParseError: Error {
  case invalid
}

struct BadString: Error, RawRepresentable {
  let rawValue: String
}

extension UInt8 {
  var isASCII: Bool {
    return self < 0x80
  }

  var isASCIIDigit: Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
  }
}

public struct Tokenizer {
  let src: String
  var input: String.UTF8View {
    src.utf8
  }
  var _position: Int
  var currentLineStartPosition: Int
  var currentLineNumber: Int
  var varOrEnvFunctions: SeenStatus
  var sourceMapUrl: String?
  var sourceUrl: String?

  init(input: String) {
    self.src = input
    self._position = 0
    self.currentLineStartPosition = 0
    self.currentLineNumber = 0
    self.varOrEnvFunctions = .dontCare
    self.sourceMapUrl = nil
    self.sourceUrl = nil
  }

  mutating func lookForVarOrEnvFunctions() {
    self.varOrEnvFunctions = .lookingForThem
  }

  mutating func seenVarOrEnvFunctions() -> Bool {
    let seen = self.varOrEnvFunctions == .seenAtLeastOne
    self.varOrEnvFunctions = .dontCare
    return seen
  }

  mutating func seeFunction(name: String) {
    if self.varOrEnvFunctions == .lookingForThem
      && (name.lowercased() == "var" || name.lowercased() == "env")
    {
      self.varOrEnvFunctions = .seenAtLeastOne
    }
  }

  mutating func next() -> Result<Token, CSSParseError> {
    nextToken(tokenizer: &self)
  }

  public var position: SourcePosition {
    get {
      SourcePosition(_position)
    }
    set {
      _position = newValue.byteIndex
    }
  }

  public var currentSourceLocation: SourceLocation {
    SourceLocation(
      line: currentLineNumber,
      column: _position - currentLineStartPosition + 1)
  }

  public var state: ParserState {
    get {
      ParserState(
        position: _position,
        currentLineStartPosition: currentLineStartPosition,
        currentLineNumber: currentLineNumber,
        atStartOf: nil)
    }
    set {
      _position = newValue.position
      currentLineStartPosition = newValue.currentLineStartPosition
      currentLineNumber = newValue.currentLineNumber
    }
  }

  mutating public func reset(state: ParserState) {
    _position = state.position
    currentLineStartPosition = state.currentLineStartPosition
    currentLineNumber = state.currentLineNumber
  }

  public func slice(from startPos: SourcePosition) -> String {
    let start = input.index(input.startIndex, offsetBy: startPos.byteIndex)
    let end = input.index(input.startIndex, offsetBy: _position)
    return String(decoding: input[start..<end], as: UTF8.self)
  }

  public func slice(range: Range<SourcePosition>) -> String {
    let start = input.index(input.startIndex, offsetBy: range.lowerBound.byteIndex)
    let end = input.index(input.startIndex, offsetBy: range.upperBound.byteIndex)
    return String(decoding: input[start..<end], as: UTF8.self)
  }

  public var currentSourceLine: String {
    let current = position
    let startSlice = slice(range: SourcePosition(0)..<current).utf8
    let start =
      startSlice.lastIndex(where: { $0 == UInt8(ascii: "\r") || $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\u{000C}") })
      .map({ startSlice.distance(from: startSlice.startIndex, to: $0) + 1 }) ?? 0

    let endSlice = slice(range: current..<SourcePosition(input.count)).utf8
    let end =
      endSlice
      .firstIndex(where: { $0 == UInt8(ascii: "\r") || $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\u{000C}") })
      .map({ endSlice.distance(from: endSlice.startIndex, to: $0) + current.byteIndex }) ?? input.count

    return slice(range: SourcePosition(start)..<SourcePosition(end))
  }

  public func nextByte() -> UInt8? {
    guard !isEof else { return nil }
    return input[input.index(input.startIndex, offsetBy: _position)]
  }

  var isEof: Bool {
    !hasAtLeast(0)
  }

  func hasAtLeast(_ n: Int) -> Bool {
    _position + n < input.count
  }

  mutating public func advance(_ n: Int) {
    _position += n
  }

  mutating public func consume4ByteIntro() {
    _ = nextByteUnchecked()
    currentLineStartPosition &-= 1
    _position += 1
  }

  mutating func consumeContinuationByte() {
    precondition((nextByteUnchecked() & 0xC0) == 0x80)
    currentLineStartPosition &+= 1
    _position += 1
  }

  mutating func consumeKnownByte(byte: UInt8) {
    assert(byte != UInt8(ascii: "\r") && byte != UInt8(ascii: "\n") && byte != UInt8(ascii: "\u{000C}"))
    _position += 1
    if (byte & 0xF0) == 0xF0 {
      currentLineStartPosition &-= 1
    } else if (byte & 0xC0) == 0x80 {
      currentLineStartPosition &+= 1
    }
  }

  func nextChar() -> Character {
    let utf8Index = input.index(input.startIndex, offsetBy: _position)
    guard let index = String.Index(utf8Index, within: src) else {
      fatalError("index out of range")
    }
    return src[index]
  }

  mutating func consumeNewline() {
    let byte = nextByteUnchecked()
    assert(byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\u{000C}"))
    _position += 1
    if byte == UInt8(ascii: "\r"), nextByte() == UInt8(ascii: "\n") {
      _position += 1
    }
    self.currentLineStartPosition = _position
    currentLineNumber += 1
  }

  func hasNewline(at offset: Int) -> Bool {
    guard _position + offset < input.count else { return false }
    let byte = byteAt(offset)
    switch byte {
    case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\u{000C}"):
      return true
    default:
      return false
    }
  }

  mutating func consumeChar() -> Character {
    let char = nextChar()
    let byteCount = char.utf8.count
    _position += byteCount
    currentLineStartPosition &+= byteCount - char.utf16.count
    return char
  }

  func startsWith(_ needle: [UInt8]) -> Bool {
    input[input.index(input.startIndex, offsetBy: _position)...].starts(with: needle)
  }

  mutating public func skipWhitespace() {
    loop: while !isEof {
      switch nextByteUnchecked() {
      case UInt8(ascii: " "), UInt8(ascii: "\t"):
        advance(1)
      case UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"), UInt8(ascii: "\r"):
        consumeNewline()
      case UInt8(ascii: "/"):
        if startsWith([UInt8(ascii: "/"), UInt8(ascii: "*")]) {
          _ = consumeComment(tokenizer: &self)
        }
      default:
        break loop
      }
    }
  }

  mutating public func skipCdcAndCdo() {
    loop: while !isEof {
      let byte = nextByteUnchecked()
      switch byte {
      case UInt8(ascii: " "), UInt8(ascii: "\t"):
        advance(1)
      case UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"), UInt8(ascii: "\r"):
        consumeNewline()
      case UInt8(ascii: "/"):
        if startsWith([UInt8(ascii: "/"), UInt8(ascii: "*")]) {
          _ = consumeComment(tokenizer: &self)
        }
      case UInt8(ascii: "<"):
        if startsWith([UInt8(ascii: "<"), UInt8(ascii: "!"), UInt8(ascii: "-"), UInt8(ascii: "-")]) {
          advance(4)
        }
      case UInt8(ascii: "-"):
        if startsWith([UInt8(ascii: "-"), UInt8(ascii: "-"), UInt8(ascii: ">")]) {
          advance(3)
        }
      default:
        break loop
      }
    }
  }

  func nextByteUnchecked() -> UInt8 {
    byteAt(0)
  }

  func byteAt(_ offset: Int) -> UInt8 {
    let position = input.index(input.startIndex, offsetBy: _position + offset)
    return input[position]
  }
}

public struct SourcePosition {
  public let byteIndex: Int

  public init(_ byteIndex: Int) {
    self.byteIndex = byteIndex
  }
}

extension SourcePosition: Comparable {
  public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
    lhs.byteIndex < rhs.byteIndex
  }
}

public struct SourceLocation: Sendable, Hashable {
  public let line: Int
  public let column: Int

  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
}

private func nextToken(tokenizer: inout Tokenizer) -> Result<Token, CSSParseError> {
  if tokenizer.isEof {
    return .failure(.invalid)
  }
  let byte = tokenizer.nextByteUnchecked()
  switch byte {
  case UInt8(ascii: " "), UInt8(ascii: "\t"):
    return .success(consumeWhitespace(tokenizer: &tokenizer, newline: false))
  case UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"), UInt8(ascii: "\r"):
    return .success(consumeWhitespace(tokenizer: &tokenizer, newline: true))
  case UInt8(ascii: "\""):
    return .success(consumeString(tokenizer: &tokenizer, singleQuote: false))
  case UInt8(ascii: "#"):
    tokenizer.advance(1)
    if isIdentStart(tokenizer: tokenizer) {
      return .success(.idHash(consumeName(tokenizer: &tokenizer)))
    } else if !tokenizer.isEof,
      [
        UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"), UInt8(ascii: "4"), UInt8(ascii: "5"),
        UInt8(ascii: "6"), UInt8(ascii: "7"), UInt8(ascii: "8"), UInt8(ascii: "9"), UInt8(ascii: "-"),
      ].contains(tokenizer.nextByteUnchecked())
    {
      return .success(.hash(consumeName(tokenizer: &tokenizer)))
    } else {
      return .success(.delim("#"))
    }
  case UInt8(ascii: "$"):
    if tokenizer.startsWith([UInt8(ascii: "$"), UInt8(ascii: "=")]) {
      tokenizer.advance(2)
      return .success(.suffixMatch)
    } else {
      tokenizer.advance(1)
      return .success(.delim("$"))
    }
  case UInt8(ascii: "'"): return .success(consumeString(tokenizer: &tokenizer, singleQuote: true))
  case UInt8(ascii: "("):
    tokenizer.advance(1)
    return .success(.parenthesisBlock)
  case UInt8(ascii: ")"):
    tokenizer.advance(1)
    return .success(.closeParenthesis)
  case UInt8(ascii: "*"):
    if tokenizer.startsWith([UInt8(ascii: "*"), UInt8(ascii: "=")]) {
      tokenizer.advance(2)
      return .success(.substringMatch)
    } else {
      tokenizer.advance(1)
      return .success(.delim("*"))
    }
  case UInt8(ascii: "+"):
    if (tokenizer.hasAtLeast(1) && tokenizer.byteAt(1).isASCIIDigit) || (tokenizer.hasAtLeast(2) && tokenizer.byteAt(1) == UInt8(ascii: ".") && tokenizer.byteAt(2).isASCIIDigit) {
      return .success(consumeNumeric(tokenizer: &tokenizer))
    } else {
      tokenizer.advance(1)
      return .success(.delim("+"))
    }
  case UInt8(ascii: ","):
    tokenizer.advance(1)
    return .success(.comma)
  case UInt8(ascii: "-"):
    if (tokenizer.hasAtLeast(1) && tokenizer.byteAt(1).isASCIIDigit) || (tokenizer.hasAtLeast(2) && tokenizer.byteAt(1) == UInt8(ascii: ".") && tokenizer.byteAt(2).isASCIIDigit) {
      return .success(consumeNumeric(tokenizer: &tokenizer))
    } else if tokenizer.startsWith([UInt8(ascii: "-"), UInt8(ascii: "-"), UInt8(ascii: ">")]) {
      tokenizer.advance(3)
      return .success(.cdc)
    } else if isIdentStart(tokenizer: tokenizer) {
      return .success(consumeIdentLike(tokenizer: &tokenizer))
    } else {
      tokenizer.advance(1)
      return .success(.delim("-"))
    }
  case UInt8(ascii: "."):
    if tokenizer.hasAtLeast(1) && tokenizer.byteAt(1).isASCIIDigit {
      return .success(consumeNumeric(tokenizer: &tokenizer))
    } else {
      tokenizer.advance(1)
      return .success(.delim("."))
    }
  case UInt8(ascii: "/"):
    if tokenizer.startsWith([UInt8(ascii: "/"), UInt8(ascii: "*")]) {
      return .success(.comment(consumeComment(tokenizer: &tokenizer)))
    } else {
      tokenizer.advance(1)
      return .success(.delim("/"))
    }
  case UInt8(ascii: "0")...UInt8(ascii: "9"): return .success(consumeNumeric(tokenizer: &tokenizer))
  case UInt8(ascii: ":"):
    tokenizer.advance(1)
    return .success(.colon)
  case UInt8(ascii: ";"):
    tokenizer.advance(1)
    return .success(.semicolon)
  case UInt8(ascii: "<"):
    if tokenizer.startsWith([UInt8(ascii: "<"), UInt8(ascii: "!"), UInt8(ascii: "-"), UInt8(ascii: "-")]) {
      tokenizer.advance(4)
      return .success(.cdo)
    } else {
      tokenizer.advance(1)
      return .success(.delim("<"))
    }
  case UInt8(ascii: "@"):
    tokenizer.advance(1)
    if isIdentStart(tokenizer: tokenizer) {
      return .success(.atKeyword(consumeName(tokenizer: &tokenizer)))
    } else {
      return .success(.delim("@"))
    }
  case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "_"), UInt8(ascii: "\0"):
    return .success(consumeIdentLike(tokenizer: &tokenizer))
  case UInt8(ascii: "["):
    tokenizer.advance(1)
    return .success(.squareBracketBlock)
  case UInt8(ascii: "\\"):
    if !tokenizer.hasNewline(at: 1) {
      return .success(consumeIdentLike(tokenizer: &tokenizer))
    } else {
      tokenizer.advance(1)
      return .success(.delim("\\"))
    }
  case UInt8(ascii: "]"):
    tokenizer.advance(1)
    return .success(.closeSquareBracket)
  case UInt8(ascii: "^"):
    if tokenizer.startsWith([UInt8(ascii: "^"), UInt8(ascii: "=")]) {
      tokenizer.advance(2)
      return .success(.prefixMatch)
    } else {
      tokenizer.advance(1)
      return .success(.delim("^"))
    }
  case UInt8(ascii: "{"):
    tokenizer.advance(1)
    return .success(.curlyBracketBlock)
  case UInt8(ascii: "|"):
    if tokenizer.startsWith([UInt8(ascii: "|"), UInt8(ascii: "=")]) {
      tokenizer.advance(2)
      return .success(.dashMatch)
    } else {
      tokenizer.advance(1)
      return .success(.delim("|"))
    }
  case UInt8(ascii: "}"):
    tokenizer.advance(1)
    return .success(.closeCurlyBracket)
  case UInt8(ascii: "~"):
    if tokenizer.startsWith([UInt8(ascii: "~"), UInt8(ascii: "=")]) {
      tokenizer.advance(2)
      return .success(.includeMatch)
    } else {
      tokenizer.advance(1)
      return .success(.delim("~"))
    }
  case let b:
    if !b.isASCII {
      return .success(consumeIdentLike(tokenizer: &tokenizer))
    } else {
      tokenizer.advance(1)
      return .success(.delim(.init(.init(b))))
    }
  }
}

private func consumeWhitespace(tokenizer: inout Tokenizer, newline: Bool) -> Token {
  let startPosition = tokenizer.position
  if newline {
    _ = tokenizer.nextByteUnchecked()
  } else {
    tokenizer.advance(1)
  }
  loop: while !tokenizer.isEof {
    switch tokenizer.nextByteUnchecked() {
    case UInt8(ascii: " "), UInt8(ascii: "\t"):
      tokenizer.advance(1)
    case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\u{000C}"):
      tokenizer.consumeNewline()
    default:
      break loop
    }
  }
  return .whitespace(tokenizer.slice(from: startPosition))
}

func checkForSourceMap(tokenizer: inout Tokenizer, contents: String) {
  let pattern = try! Regex("[ \t\u{000C}\r\n]")
  do {
    let directive = "# sourceMappingURL="
    let directiveOld = "@ sourceMappingURL="
    if contents.starts(with: directive) || contents.starts(with: directiveOld) {
      let contents = contents[contents.index(contents.startIndex, offsetBy: directive.count)...]
      tokenizer.sourceMapUrl = contents.split(separator: pattern, omittingEmptySubsequences: false).first.flatMap(String.init)
    }
  }
  do {
    let directive = "# sourceURL="
    let directiveOld = "@ sourceURL="
    if contents.starts(with: directive) || contents.starts(with: directiveOld) {
      let contents = contents[contents.index(contents.startIndex, offsetBy: directive.count)...]
      tokenizer.sourceUrl = contents.split(separator: pattern, omittingEmptySubsequences: false).first.flatMap(String.init)
    }
  }
}

func consumeComment(tokenizer: inout Tokenizer) -> String {
  tokenizer.advance(2)
  let startPosition = tokenizer.position
  while !tokenizer.isEof {
    switch tokenizer.nextByteUnchecked() {
    case UInt8(ascii: "*"):
      let endPosition = tokenizer.position
      tokenizer.advance(1)
      if tokenizer.nextByte() == UInt8(ascii: "/") {
        tokenizer.advance(1)
        let contents = tokenizer.slice(range: startPosition..<endPosition)
        checkForSourceMap(tokenizer: &tokenizer, contents: contents)
        return contents
      }
    case UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"), UInt8(ascii: "\r"):
      tokenizer.consumeNewline()
    case 0x80...0xBF:
      tokenizer.consumeContinuationByte()
    case 0xF0...0xFF:
      tokenizer.consume4ByteIntro()
    default:
      tokenizer.advance(1)
    }
  }
  let contents = tokenizer.slice(from: startPosition)
  checkForSourceMap(tokenizer: &tokenizer, contents: contents)
  return contents
}

func consumeString(tokenizer: inout Tokenizer, singleQuote: Bool) -> Token {
  switch consumeQuotedString(tokenizer: &tokenizer, singleQuote: singleQuote) {
  case .success(let value):
    return .quotedString(value)
  case .failure(let badString):
    return .badString(badString.rawValue)
  }
}

func consumeQuotedString(tokenizer: inout Tokenizer, singleQuote: Bool) -> Result<String, BadString> {
  tokenizer.advance(1)
  let startPos = tokenizer.position
  var stringBytes: [UInt8] = []
  loop: while true {
    if tokenizer.isEof {
      return .success(tokenizer.slice(from: startPos))
    }
    let byte = tokenizer.nextByteUnchecked()
    switch byte {
    case UInt8(ascii: "\""):
      if !singleQuote {
        let value = tokenizer.slice(from: startPos)
        tokenizer.advance(1)
        return .success(value)
      }
      tokenizer.advance(1)
    case UInt8(ascii: "'"):
      if singleQuote {
        let value = tokenizer.slice(from: startPos)
        tokenizer.advance(1)
        return .success(value)
      }
      tokenizer.advance(1)
    case UInt8(ascii: "\\"), UInt8(ascii: "\0"):
      stringBytes = Array(tokenizer.slice(from: startPos).utf8)
      break loop
    case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\u{000C}"):
      return .failure(.init(rawValue: tokenizer.slice(from: startPos)))
    case 0x80...0xBF:
      tokenizer.consumeContinuationByte()
    case 0xF0...0xFF:
      tokenizer.consume4ByteIntro()
    default:
      tokenizer.advance(1)
    }
  }
  endLoop: while !tokenizer.isEof {
    let byte = tokenizer.nextByteUnchecked()
    switch byte {
    case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\u{000C}"):
      return .failure(.init(rawValue: String(decoding: stringBytes, as: UTF8.self)))
    case UInt8(ascii: "\""):
      tokenizer.advance(1)
      if !singleQuote {
        break endLoop
      }
    case UInt8(ascii: "'"):
      tokenizer.advance(1)
      if singleQuote {
        break endLoop
      }
    case UInt8(ascii: "\\"):
      tokenizer.advance(1)
      if !tokenizer.isEof {
        switch tokenizer.nextByteUnchecked() {
        case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\u{000C}"):
          tokenizer.consumeNewline()
        default:
          consumeEscapeAndWrite(tokenizer: &tokenizer, bytes: &stringBytes)
        }
      }
      continue
    case UInt8(ascii: "\0"):
      tokenizer.advance(1)
      stringBytes.append(0xFF)
      continue
    case 0x80...0xBF:
      tokenizer.consumeContinuationByte()
    case 0xF0...0xFF:
      tokenizer.consume4ByteIntro()
    default:
      tokenizer.advance(1)
    }
    stringBytes.append(byte)
  }
  return .success(String(decoding: stringBytes, as: UTF8.self))
}

func isIdentStart(tokenizer: Tokenizer) -> Bool {
  guard !tokenizer.isEof else { return false }
  switch tokenizer.nextByteUnchecked() {
  case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "_"), UInt8(ascii: "\0"):
    return true
  case UInt8(ascii: "-"):
    guard tokenizer.hasAtLeast(1) else { return false }
    switch tokenizer.byteAt(1) {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "\0"):
      return true
    case UInt8(ascii: "\\"):
      return !tokenizer.hasNewline(at: 1)
    case let b:
      return !b.isASCII
    }
  case UInt8(ascii: "\\"):
    return !tokenizer.hasNewline(at: 1)
  case let b:
    return !b.isASCII
  }
}

func consumeIdentLike(tokenizer: inout Tokenizer) -> Token {
  let value = consumeName(tokenizer: &tokenizer)
  if !tokenizer.isEof, tokenizer.nextByteUnchecked() == UInt8(ascii: "(") {
    tokenizer.advance(1)
    if value.caseInsensitiveCompare("url") == .orderedSame {
      return consumeUnquotedUrl(tokenizer: &tokenizer) ?? .function(value)
    } else {
      tokenizer.seeFunction(name: value)
      return .function(value)
    }
  } else {
    return .ident(value)
  }
}

func consumeName(tokenizer: inout Tokenizer) -> String {
  let startPos = tokenizer.position
  var valueBytes: [UInt8] = []
  startLoop: while true {
    if tokenizer.isEof {
      return tokenizer.slice(from: startPos)
    }
    switch tokenizer.nextByteUnchecked() {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
      UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"):
      tokenizer.advance(1)
    case UInt8(ascii: "\\"), UInt8(ascii: "\0"):
      valueBytes = [UInt8](tokenizer.slice(from: startPos).utf8)
      break startLoop
    case 0x80...0xBF:
      tokenizer.consumeContinuationByte()
    case 0xC0...0xEF:
      tokenizer.advance(1)
    case 0xF0...0xFF:
      tokenizer.consume4ByteIntro()
    default:
      return tokenizer.slice(from: startPos)
    }
  }

  terminateLoop: while !tokenizer.isEof {
    let b = tokenizer.nextByteUnchecked()
    switch b {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
      UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"):
      tokenizer.advance(1)
      valueBytes.append(b)
    case UInt8(ascii: "\\"):
      if tokenizer.hasNewline(at: 1) { break }
      tokenizer.advance(1)
      consumeEscapeAndWrite(tokenizer: &tokenizer, bytes: &valueBytes)
    case UInt8(ascii: "\0"):
      tokenizer.advance(1)
      valueBytes.append(contentsOf: replacementChar.utf8)
    case 0x80...0xBF:
      tokenizer.consumeContinuationByte()
      valueBytes.append(b)
    case 0xC0...0xEF:
      tokenizer.advance(1)
      valueBytes.append(b)
    case 0xF0...0xFF:
      tokenizer.consume4ByteIntro()
      valueBytes.append(b)
    default:
      break terminateLoop
    }
  }
  return String(decoding: valueBytes, as: UTF8.self)
}

func byteToHexDigit(_ b: UInt8) -> UInt32? {
  switch b {
  case UInt8(ascii: "0")...UInt8(ascii: "9"):
    UInt32(b - UInt8(ascii: "0"))
  case UInt8(ascii: "a")...UInt8(ascii: "f"):
    UInt32(b - UInt8(ascii: "a")) + 10
  case UInt8(ascii: "A")...UInt8(ascii: "F"):
    UInt32(b - UInt8(ascii: "A")) + 10
  default:
    nil
  }
}

func byteToDecimalDigit(_ b: UInt8) -> UInt32? {
  if b.isASCIIDigit { UInt32(b - UInt8(ascii: "0")) } else { nil }
}

func consumeNumeric(tokenizer: inout Tokenizer) -> Token {
  let (hasSign, sign) =
    switch tokenizer.nextByteUnchecked() {
    case UInt8(ascii: "-"): (true, -1.0)
    case UInt8(ascii: "+"): (true, 1.0)
    default: (false, 1.0)
    }
  if hasSign {
    tokenizer.advance(1)
  }

  var integralPart: Float64 = 0
  while let digit = byteToDecimalDigit(tokenizer.nextByteUnchecked()) {
    integralPart = integralPart * 10.0 + Float64(digit)
    tokenizer.advance(1)
    if tokenizer.isEof {
      break
    }
  }
  var isInteger = true
  var fractional_part: Float64 = 0
  fractionalLoop: if tokenizer.hasAtLeast(1),
    tokenizer.nextByteUnchecked() == UInt8(ascii: "."),
    tokenizer.byteAt(1).isASCIIDigit
  {
    isInteger = false
    tokenizer.advance(1)  // Consume '.'
    var factor: Float64 = 0.1
    while let digit = byteToDecimalDigit(tokenizer.nextByteUnchecked()) {
      fractional_part += Float64(digit) * factor
      factor *= 0.1
      tokenizer.advance(1)
      if tokenizer.isEof {
        break fractionalLoop
      }
    }
  }

  var value = sign * (integralPart + fractional_part)

  if tokenizer.hasAtLeast(1) && [UInt8(ascii: "e"), UInt8(ascii: "E")].contains(tokenizer.nextByteUnchecked()) && (tokenizer.byteAt(1).isASCIIDigit || (tokenizer.hasAtLeast(2) && [UInt8(ascii: "+"), UInt8(ascii: "-")].contains(tokenizer.byteAt(1)) && tokenizer.byteAt(2).isASCIIDigit)) {
    isInteger = false
    tokenizer.advance(1)
    let (hasSign, sign) =
      switch tokenizer.nextByteUnchecked() {
      case UInt8(ascii: "-"): (true, -1.0)
      case UInt8(ascii: "+"): (true, 1.0)
      default: (false, 1.0)
      }
    if hasSign {
      tokenizer.advance(1)
    }
    var exponent: Float64 = 0
    while let digit = byteToDecimalDigit(tokenizer.nextByteUnchecked()) {
      exponent = exponent * 10.0 + Float64(digit)
      tokenizer.advance(1)
      if tokenizer.isEof {
        break
      }
    }
    value *= pow(10.0, sign * exponent)
  }

  let intValue: Int32? =
    if isInteger {
      value >= Float64(Int32.max) ? Int32.max : (value <= Float64(Int32.min) ? Int32.min : Int32(exactly: value) ?? 0)
    } else {
      nil
    }

  if !tokenizer.isEof, tokenizer.nextByteUnchecked() == UInt8(ascii: "%") {
    tokenizer.advance(1)
    return .percentage(
      .init(
        unitValue: Float32(value / 100.0),
        intValue: intValue,
        hasSign: hasSign
      ))
  }

  if isIdentStart(tokenizer: tokenizer) {
    let unit = consumeName(tokenizer: &tokenizer)
    return .dimention(.init(value: Float32(value), intValue: intValue, hasSign: hasSign, unit: unit))
  } else {
    return .number(.init(value: Float32(value), intValue: intValue, hasSign: hasSign))
  }
}

func consumeUnquotedUrl(tokenizer: inout Tokenizer) -> Token? {
  let startPosition = tokenizer.position
  let input = tokenizer.input
  let fromStart = input[input.index(input.startIndex, offsetBy: startPosition.byteIndex)...]
  var newlines: Int = 0
  var lastNewline: Int = 0
  var foundPrintableChar = false
  var index = fromStart.startIndex

  loop: while true {
    guard index < fromStart.endIndex else {
      tokenizer.position = .init(input.count)
      break loop
    }
    let b = fromStart[index]
    switch b {
    case UInt8(ascii: " "), UInt8(ascii: "\t"):
      break
    case UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"):
      newlines += 1
      lastNewline = fromStart.distance(from: fromStart.startIndex, to: index)
    case UInt8(ascii: "\r"):
      if fromStart[fromStart.index(after: index)] == UInt8(ascii: "\n") {
        newlines += 1
        lastNewline = fromStart.distance(from: fromStart.startIndex, to: index)
      }
    case UInt8(ascii: "\""), UInt8(ascii: "\'"):
      return nil
    case UInt8(ascii: ")"):
      tokenizer.position = .init(tokenizer.position.byteIndex + fromStart.distance(from: fromStart.startIndex, to: index) + 1)
      break loop
    default:
      tokenizer.position = .init(tokenizer.position.byteIndex + fromStart.distance(from: fromStart.startIndex, to: index))
      foundPrintableChar = true
      break loop
    }
    index = fromStart.index(after: index)
  }

  if newlines > 0 {
    tokenizer.currentLineNumber += newlines
    tokenizer.currentLineStartPosition = startPosition.byteIndex + lastNewline + 1
  }

  if foundPrintableChar {
    return consumeUnquotedUrlInternal(tokenizer: &tokenizer)
  } else {
    return .unquotedUrl("")
  }

  func consumeUnquotedUrlInternal(tokenizer: inout Tokenizer) -> Token {
    let startPos = tokenizer.position
    var stringBytes: [UInt8] = []
    startLoop: while true {
      if tokenizer.isEof {
        return .unquotedUrl(tokenizer.slice(from: startPos))
      }
      switch tokenizer.nextByteUnchecked() {
      case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"):
        let value = tokenizer.slice(from: startPos)
        return consumeUrlEnd(tokenizer: &tokenizer, startPos: startPos, string: value)
      case UInt8(ascii: ")"):
        let value = tokenizer.slice(from: startPos)
        tokenizer.advance(1)
        return .unquotedUrl(value)
      case 0x01...0x08, 0x0B, 0x0E...0x1F, 0x7F, UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "("):
        tokenizer.advance(1)
        return consumeBadUrl(tokenizer: &tokenizer, startPos: startPos)
      case UInt8(ascii: "\\"), UInt8(ascii: "\0"):
        stringBytes = Array(tokenizer.slice(from: startPos).utf8)
        break startLoop
      case 0x80...0xBF:
        tokenizer.consumeContinuationByte()
      case 0xF0...0xFF:
        tokenizer.consume4ByteIntro()
      default:
        tokenizer.advance(1)
      }
    }

    terminateLoop: while !tokenizer.isEof {
      let b = tokenizer.nextByteUnchecked()
      switch b {
      case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"):
        let string = String(decoding: stringBytes, as: UTF8.self)
        return consumeUrlEnd(tokenizer: &tokenizer, startPos: startPos, string: string)
      case UInt8(ascii: ")"):
        tokenizer.advance(1)
        break terminateLoop
      case 0x01...0x08, 0x0B, 0x0E...0x1F, 0x7F, UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "("):
        tokenizer.advance(1)
        return consumeBadUrl(tokenizer: &tokenizer, startPos: startPos)
      case UInt8(ascii: "\\"):
        tokenizer.advance(1)
        if tokenizer.hasNewline(at: 0) {
          return consumeBadUrl(tokenizer: &tokenizer, startPos: startPos)
        }
        consumeEscapeAndWrite(tokenizer: &tokenizer, bytes: &stringBytes)
      case UInt8(ascii: "\0"):
        tokenizer.advance(1)
        stringBytes.append(contentsOf: replacementChar.utf8)
      case 0x80...0xBF:
        tokenizer.consumeContinuationByte()
        stringBytes.append(b)
      case 0xF0...0xFF:
        tokenizer.consume4ByteIntro()
        stringBytes.append(b)
      default:
        tokenizer.advance(1)
        stringBytes.append(b)
      }
    }
    return .unquotedUrl(String(decoding: stringBytes, as: UTF8.self))
  }

  func consumeUrlEnd(tokenizer: inout Tokenizer, startPos: SourcePosition, string: String) -> Token {
    loop: while !tokenizer.isEof {
      switch tokenizer.nextByteUnchecked() {
      case UInt8(ascii: ")"):
        tokenizer.advance(1)
        break loop
      case UInt8(ascii: " "), UInt8(ascii: "\t"):
        tokenizer.advance(1)
      case UInt8(ascii: "\n"), UInt8(ascii: "\u{0C}"), UInt8(ascii: "\r"):
        tokenizer.consumeNewline()
      case let b:
        tokenizer.consumeKnownByte(byte: b)
        return consumeBadUrl(tokenizer: &tokenizer, startPos: startPos)
      }
    }
    return .unquotedUrl(string)
  }

  func consumeBadUrl(tokenizer: inout Tokenizer, startPos: SourcePosition) -> Token {
    while !tokenizer.isEof {
      switch tokenizer.nextByteUnchecked() {
      case UInt8(ascii: ")"):
        let contents = tokenizer.slice(from: startPos)
        tokenizer.advance(1)
        return .badUrl(contents)
      case UInt8(ascii: "\\"):
        tokenizer.advance(1)
        switch tokenizer.nextByte() {
        case UInt8(ascii: ")"), UInt8(ascii: "\\"):
          tokenizer.advance(1)
        default:
          break
        }
      case UInt8(ascii: "\n"), UInt8(ascii: "\u{0C}"), UInt8(ascii: "\r"):
        tokenizer.consumeNewline()
      case let b:
        tokenizer.consumeKnownByte(byte: b)
      }
    }
    return .badUrl(tokenizer.slice(from: startPos))
  }
}

func consumeHexDigits(tokenizer: inout Tokenizer) -> (UInt32, UInt32) {
  var value: UInt32 = 0
  var digits: UInt32 = 0
  while digits < 6 && !tokenizer.isEof {
    guard let digit = byteToHexDigit(tokenizer.nextByteUnchecked()) else { break }
    value = value * 16 + digit
    digits += 1
    tokenizer.advance(1)
  }
  return (value, digits)
}

func consumeEscapeAndWrite(tokenizer: inout Tokenizer, bytes: inout [UInt8]) {
  let c = consumeEscape(tokenizer: &tokenizer)
  bytes.append(contentsOf: c.utf8)
}

let replacementChar: Character = "\u{FFFD}"

func consumeEscape(tokenizer: inout Tokenizer) -> Character {
  if tokenizer.isEof {
    return replacementChar
  }
  switch tokenizer.nextByteUnchecked() {
  case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "A")...UInt8(ascii: "F"), UInt8(ascii: "a")...UInt8(ascii: "f"):
    let (c, _) = consumeHexDigits(tokenizer: &tokenizer)
    if !tokenizer.isEof {
      switch tokenizer.nextByteUnchecked() {
      case UInt8(ascii: " "), UInt8(ascii: "\t"):
        tokenizer.advance(1)
      case UInt8(ascii: "\n"), UInt8(ascii: "\u{000C}"), UInt8(ascii: "\r"):
        tokenizer.consumeNewline()
      default:
        break
      }
    }
    if c != 0 {
      return UnicodeScalar(c).flatMap({ .init($0) }) ?? replacementChar
    } else {
      return replacementChar
    }
  case UInt8(ascii: "\0"):
    tokenizer.advance(1)
    return replacementChar
  default:
    return tokenizer.consumeChar()
  }
}
