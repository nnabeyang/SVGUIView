import Foundation
import Testing

@testable import _CSSParser

@Suite("Tokenizer")
struct TokenizerTests {
  @Test("UTF8 slice index and distance are correct")
  func utf8SliceIndexAndDistance() {
    let str = "Hello World".utf8
    let fromStart = str[str.index(str.startIndex, offsetBy: 6)...]
    let index = fromStart.startIndex
    #expect(fromStart[index] == UInt8(ascii: "W"))
    #expect(fromStart.distance(from: index, to: fromStart.endIndex) == 5)
  }

  @Test("Tokenizer.slice returns color substring")
  func tokenizerSlice_ReturnsColorSubstring() throws {
    let tokenizer = Tokenizer(input: "p { color: blue;}")
    let start = SourcePosition(4)
    let end = SourcePosition(9)
    #expect(tokenizer.slice(range: start..<end) == "color")
  }

  @Test("currentSourceLine returns first line content")
  func currentSourceLine_ReturnsFirstLineContent() throws {
    let input = #"""
      p { color: blue;}
      h1 { color: red;}
      """#
    let tokenizer = Tokenizer(input: input)
    #expect(tokenizer.currentSourceLine == "p { color: blue;}")
  }

  @Test("nextChar peeks without consuming")
  func nextChar_PeeksFirstCharacterWithoutConsuming() throws {
    let input = #"""
      p { color: blue;}
      h1 { color: red;}
      """#
    var tokenizer = Tokenizer(input: input)
    #expect(tokenizer.nextChar() == "p")
    #expect(tokenizer.consumeChar() == "p", "nextChar should not consume the character")
  }

  @Test("consumeChar handles extended grapheme clusters")
  func consumeChar_HandlesExtendedGraphemeClusters() throws {
    let input = "p🧑‍🧑‍🧒‍🧒q"
    var tokenizer = Tokenizer(input: input)
    #expect(tokenizer.consumeChar() == "p")
    #expect(tokenizer.consumeChar() == "🧑‍🧑‍🧒‍🧒")
    #expect(tokenizer.consumeChar() == "q")
  }

  @Test("consumeQuotedString succeeds and returns string")
  func consumeQuotedString_Success() throws {
    let input = #""Hello, World" vvv"#
    var tokenizer = Tokenizer(input: input)
    guard case .success(let value) = consumeQuotedString(tokenizer: &tokenizer, singleQuote: false) else {
      Issue.record("Expected success")
      return
    }
    #expect(value == "Hello, World")
  }

  @Test("consumeNumeric parses number token")
  func consumeNumeric_NumberTokenParsing() throws {
    let input = #"-123.456"#
    var tokenizer = Tokenizer(input: input)
    guard case .number(let value) = consumeNumeric(tokenizer: &tokenizer) else {
      Issue.record("Expected number token")
      return
    }
    #expect(abs(value.value - -123.456) <= 0.0001)
    #expect(value.intValue == nil)
    #expect(value.hasSign)
  }

  @Test("consumeQuotedString unterminated returns failure")
  func consumeQuotedString_Unterminated_ReturnsFailure() throws {
    let input = #"""
      "Hello,
       World" vvv
      """#
    var tokenizer = Tokenizer(input: input)
    guard case .failure(let value) = consumeQuotedString(tokenizer: &tokenizer, singleQuote: false) else {
      Issue.record("Expected failure")
      return
    }
    #expect(value.rawValue == "Hello,")
  }

  @Test("detects sourceMappingURL directive")
  func detectsSourceMappingURLDirective() throws {
    let input = #"# sourceMappingURL=http://example.com/path/to/your/sourcemap.map   "#
    var tokenizer = Tokenizer(input: "")
    checkForSourceMap(tokenizer: &tokenizer, contents: input)
    #expect(tokenizer.sourceMapUrl == "http://example.com/path/to/your/sourcemap.map")
  }

  @Test("detects sourceURL directive")
  func detectsSourceURLDirective() throws {
    let input = #"# sourceURL=http://example.com/path/to/your/script.js   "#
    var tokenizer = Tokenizer(input: "")
    checkForSourceMap(tokenizer: &tokenizer, contents: input)
    #expect(tokenizer.sourceUrl == "http://example.com/path/to/your/script.js")
  }

  private func collectTokens(_ input: String, cap: Int = 100) -> [Token] {
    var tokenizer = Tokenizer(input: input)
    var tokens: [Token] = []
    var iterations = 0
    while iterations < cap {
      iterations += 1
      switch tokenizer.next() {
      case .success(let tok):
        tokens.append(tok)
      case .failure:
        return tokens
      }
    }
    return tokens
  }

  @Test("token sequence parses escaped dash ident")
  func tokenSequence_SimpleRule_NoWhitespace2() throws {
    let tokens = collectTokens("\\- -red")
    #expect(tokens[0] == .ident("-"))
  }

  @Test("token sequence for simple rule without whitespace")
  func tokenSequence_SimpleRule_NoWhitespace() throws {
    let tokens = collectTokens("p{color:blue;}")
    #expect(tokens.count == 7)
    #expect(tokens[0] == .ident("p"))
    #expect(tokens[1] == .curlyBracketBlock)
    #expect(tokens[2] == .ident("color"))
    #expect(tokens[3] == .colon)
    #expect(tokens[4] == .ident("blue"))
    #expect(tokens[5] == .semicolon)
    #expect(tokens[6] == .closeCurlyBracket)
  }

  @Test("hash variants without whitespace parse correctly")
  func tokenSequence_HashVariants_NoWhitespace() throws {
    let tokens = collectTokens("#id#123abc#")
    #expect(tokens.count == 3)
    #expect(tokens[0] == .idHash("id"))
    #expect(tokens[1] == .hash("123abc"))
    #expect(tokens[2] == .delim("#"))
  }

  @Test("@media parsed as atKeyword token")
  func atKeyword() throws {
    let tokens = collectTokens("@media")
    #expect(tokens == [.atKeyword("media")])
  }

  @Test("url(unquoted) tokenizes to unquotedUrl")
  func url_Unquoted() throws {
    let tokens = collectTokens("url(http://example.com)")
    #expect(tokens == [.unquotedUrl("http://example.com")])
  }

  @Test("url(quoted) tokenizes to function + string + close paren")
  func url_Quoted_BecomesFunctionAndString() throws {
    let tokens = collectTokens("url(\"a\")")
    #expect(tokens.count == 3)
    #expect(tokens[0] == .function("url"))
    #expect(tokens[1] == .quotedString("a"))
    #expect(tokens[2] == .closeParenthesis)
  }

  @Test("numbers, percentage, and dimension comma-separated tokenization")
  func numbers_Percentage_Dimension_CommaSeparated() throws {
    let tokens = collectTokens("10,10.5,-3e2,50%,12px")
    #expect(tokens.count == 9)

    // 10
    if case .number(let n0) = tokens[0] {
      #expect(n0.value == 10.0)
      #expect(n0.intValue == 10)
      #expect(!n0.hasSign)
    } else {
      Issue.record("Expected number token at index 0")
    }

    #expect(tokens[1] == .comma)

    // 10.5
    if case .number(let n1) = tokens[2] {
      #expect(abs(n1.value - 10.5) <= 0.0001)
      #expect(n1.intValue == nil)
      #expect(!n1.hasSign)
    } else {
      Issue.record("Expected number token at index 2")
    }

    #expect(tokens[3] == .comma)

    // -3e2
    if case .number(let n2) = tokens[4] {
      #expect(abs(n2.value - (-300.0)) <= 0.0001)
      #expect(n2.intValue == nil)
      #expect(n2.hasSign)
    } else {
      Issue.record("Expected number token at index 4")
    }

    #expect(tokens[5] == .comma)

    // 50%
    if case .percentage(let p) = tokens[6] {
      #expect(abs(p.unitValue - 0.5) <= 0.0001)
      #expect(p.intValue == 50)
      #expect(!p.hasSign)
    } else {
      Issue.record("Expected percentage token at index 6")
    }

    #expect(tokens[7] == .comma)

    // 12px
    if case .dimention(let d) = tokens[8] {
      #expect(abs(d.value - 12.0) <= 0.0001)
      #expect(d.intValue == 12)
      #expect(d.unit == "px")
      #expect(!d.hasSign)
    } else {
      Issue.record("Expected dimension token at index 8")
    }
  }

  @Test("blocks and closers tokenization order")
  func blocksAndClosers() throws {
    let tokens = collectTokens("([{}])")
    #expect(tokens.count == 6)
    #expect(tokens[0] == .parenthesisBlock)
    #expect(tokens[1] == .squareBracketBlock)
    #expect(tokens[2] == .curlyBracketBlock)
    #expect(tokens[3] == .closeCurlyBracket)
    #expect(tokens[4] == .closeSquareBracket)
    #expect(tokens[5] == .closeParenthesis)
  }

  @Test("CDO and CDC tokens parse")
  func cdoAndCDC() throws {
    #expect(collectTokens("<!--") == [.cdo])
    #expect(collectTokens("-->") == [.cdc])
  }

  @Test("comment tokenization")
  func comment() throws {
    let tokens = collectTokens("/*hello*/")
    #expect(tokens == [.comment("hello")])
  }

  @Test("delimiters and match operators tokenize correctly")
  func delimitersAndMatches() throws {
    #expect(collectTokens("$=") == [.suffixMatch])
    #expect(collectTokens("^=") == [.prefixMatch])
    #expect(collectTokens("|=") == [.dashMatch])
    #expect(collectTokens("~=") == [.includeMatch])
    #expect(collectTokens("+") == [.delim("+")])
    #expect(collectTokens("-") == [.delim("-")])
    #expect(collectTokens(".") == [.delim(".")])
    #expect(collectTokens("/") == [.delim("/")])
    #expect(collectTokens(":") == [.colon])
    #expect(collectTokens(";") == [.semicolon])
    #expect(collectTokens("<") == [.delim("<")])
    #expect(collectTokens("@") == [.delim("@")])
    #expect(collectTokens("#") == [.delim("#")])
  }

  @Test("unicode identifier tokenizes correctly")
  func unicodeIdent() throws {
    let tokens = collectTokens("色")
    #expect(tokens == [.ident("色")])
  }

  @Test("non-url function tokenizes correctly")
  func functionNonUrl() throws {
    let tokens = collectTokens("calc(")
    #expect(tokens == [.function("calc")])
  }

  @Test("consumeHexDigits and consumeEscape parse correctly")
  func consumeHexDigitsAndEscape() throws {
    do {
      var tokenizer = Tokenizer(input: "1A2bG")
      let (value, digits) = consumeHexDigits(tokenizer: &tokenizer)
      #expect(value == 0x1A2B)
      #expect(digits == 4)
    }
    do {
      var tokenizer = Tokenizer(input: "41 ")
      let c = consumeEscape(tokenizer: &tokenizer)
      #expect(String(c) == "A")
    }
  }
}
