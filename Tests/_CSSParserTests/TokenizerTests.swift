import Foundation
import XCTest

@testable import _CSSParser

final class TokenizerTests: XCTestCase {
  func testUTF8SliceIndexAndDistance() {
    let str = "Hello World".utf8
    let fromStart = str[str.index(str.startIndex, offsetBy: 6)...]
    let index = fromStart.startIndex
    XCTAssertEqual(fromStart[index], UInt8(ascii: "W"))
    XCTAssertEqual(fromStart.distance(from: index, to: fromStart.endIndex), 5)
  }

  func testTokenizerSlice_ReturnsColorSubstring() throws {
    let tokenizer = Tokenizer(input: "p { color: blue;}")
    let start = SourcePosition(4)
    let end = SourcePosition(9)
    XCTAssertEqual(tokenizer.slice(range: start..<end), "color")
  }

  func testCurrentSourceLine_ReturnsFirstLineContent() throws {
    let input = #"""
      p { color: blue;}
      h1 { color: red;}
      """#
    let tokenizer = Tokenizer(input: input)
    XCTAssertEqual(tokenizer.currentSourceLine, "p { color: blue;}")
  }

  func testNextChar_PeeksFirstCharacterWithoutConsuming() throws {
    let input = #"""
      p { color: blue;}
      h1 { color: red;}
      """#
    var tokenizer = Tokenizer(input: input)
    XCTAssertEqual(tokenizer.nextChar(), "p")
    XCTAssertEqual(tokenizer.consumeChar(), "p", "nextChar should not consume the character")
  }

  func testConsumeChar_HandlesExtendedGraphemeClusters() throws {
    let input = "p🧑‍🧑‍🧒‍🧒q"
    var tokenizer = Tokenizer(input: input)
    XCTAssertEqual(tokenizer.consumeChar(), "p")
    XCTAssertEqual(tokenizer.consumeChar(), "🧑‍🧑‍🧒‍🧒")
    XCTAssertEqual(tokenizer.consumeChar(), "q")
  }

  func testConsumeQuotedString_Success() throws {
    let input = #""Hello, World" vvv"#
    var tokenizer = Tokenizer(input: input)
    guard case .success(let value) = consumeQuotedString(tokenizer: &tokenizer, singleQuote: false) else {
      XCTFail()
      return
    }
    XCTAssertEqual(value, "Hello, World")
  }

  func testConsumeNumeric_NumberTokenParsing() throws {
    let input = #"-123.456"#
    var tokenizer = Tokenizer(input: input)
    guard case .number(let value) = consumeNumeric(tokenizer: &tokenizer) else {
      XCTFail()
      return
    }
    XCTAssertEqual(value.value, -123.456, accuracy: 0.0001)
    XCTAssertNil(value.intValue)
    XCTAssertTrue(value.hasSign)
  }

  func testConsumeQuotedString_Unterminated_ReturnsFailure() throws {
    let input = #"""
      "Hello,
       World" vvv
      """#
    var tokenizer = Tokenizer(input: input)
    guard case .failure(let value) = consumeQuotedString(tokenizer: &tokenizer, singleQuote: false) else {
      XCTFail()
      return
    }
    XCTAssertEqual(value.rawValue, "Hello,")
  }

  func testDetectsSourceMappingURLDirective() throws {
    let input = #"# sourceMappingURL=http://example.com/path/to/your/sourcemap.map   "#
    var tokenizer = Tokenizer(input: "")
    checkForSourceMap(tokenizer: &tokenizer, contents: input)
    XCTAssertEqual(tokenizer.sourceMapUrl, "http://example.com/path/to/your/sourcemap.map")
  }

  func testDetectsSourceURLDirective() throws {
    let input = #"# sourceURL=http://example.com/path/to/your/script.js   "#
    var tokenizer = Tokenizer(input: "")
    checkForSourceMap(tokenizer: &tokenizer, contents: input)
    XCTAssertEqual(tokenizer.sourceUrl, "http://example.com/path/to/your/script.js")
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

  func testTokenSequence_SimpleRule_NoWhitespace2() throws {
    let tokens = collectTokens("\\- -red")
    XCTAssertEqual(tokens[0], .ident("-"))
  }

  func testTokenSequence_SimpleRule_NoWhitespace() throws {
    let tokens = collectTokens("p{color:blue;}")
    XCTAssertEqual(tokens.count, 7)
    XCTAssertEqual(tokens[0], .ident("p"))
    XCTAssertEqual(tokens[1], .curlyBracketBlock)
    XCTAssertEqual(tokens[2], .ident("color"))
    XCTAssertEqual(tokens[3], .colon)
    XCTAssertEqual(tokens[4], .ident("blue"))
    XCTAssertEqual(tokens[5], .semicolon)
    XCTAssertEqual(tokens[6], .closeCurlyBracket)
  }

  func testTokenSequence_HashVariants_NoWhitespace() throws {
    let tokens = collectTokens("#id#123abc#")
    XCTAssertEqual(tokens.count, 3)
    XCTAssertEqual(tokens[0], .idHash("id"))
    XCTAssertEqual(tokens[1], .hash("123abc"))
    XCTAssertEqual(tokens[2], .delim("#"))
  }

  func testAtKeyword() throws {
    let tokens = collectTokens("@media")
    XCTAssertEqual(tokens, [.atKeyword("media")])
  }

  func testUrl_Unquoted() throws {
    let tokens = collectTokens("url(http://example.com)")
    XCTAssertEqual(tokens, [.unquotedUrl("http://example.com")])
  }

  func testUrl_Quoted_BecomesFunctionAndString() throws {
    let tokens = collectTokens("url(\"a\")")
    XCTAssertEqual(tokens.count, 3)
    XCTAssertEqual(tokens[0], .function("url"))
    XCTAssertEqual(tokens[1], .quotedString("a"))
    XCTAssertEqual(tokens[2], .closeParenthesis)
  }

  func testNumbers_Percentage_Dimension_CommaSeparated() throws {
    let tokens = collectTokens("10,10.5,-3e2,50%,12px")
    XCTAssertEqual(tokens.count, 9)

    // 10
    if case .number(let n0) = tokens[0] {
      XCTAssertEqual(n0.value, 10.0)
      XCTAssertEqual(n0.intValue, 10)
      XCTAssertFalse(n0.hasSign)
    } else {
      XCTFail("Expected number token at index 0")
    }

    XCTAssertEqual(tokens[1], .comma)

    // 10.5
    if case .number(let n1) = tokens[2] {
      XCTAssertEqual(n1.value, 10.5, accuracy: 0.0001)
      XCTAssertNil(n1.intValue)
      XCTAssertFalse(n1.hasSign)
    } else {
      XCTFail("Expected number token at index 2")
    }

    XCTAssertEqual(tokens[3], .comma)

    // -3e2
    if case .number(let n2) = tokens[4] {
      XCTAssertEqual(n2.value, -300.0, accuracy: 0.0001)
      XCTAssertNil(n2.intValue)
      XCTAssertTrue(n2.hasSign)
    } else {
      XCTFail("Expected number token at index 4")
    }

    XCTAssertEqual(tokens[5], .comma)

    // 50%
    if case .percentage(let p) = tokens[6] {
      XCTAssertEqual(p.unitValue, 0.5, accuracy: 0.0001)
      XCTAssertEqual(p.intValue, 50)
      XCTAssertFalse(p.hasSign)
    } else {
      XCTFail("Expected percentage token at index 6")
    }

    XCTAssertEqual(tokens[7], .comma)

    // 12px
    if case .dimention(let d) = tokens[8] {
      XCTAssertEqual(d.value, 12.0, accuracy: 0.0001)
      XCTAssertEqual(d.intValue, 12)
      XCTAssertEqual(d.unit, "px")
      XCTAssertFalse(d.hasSign)
    } else {
      XCTFail("Expected dimension token at index 8")
    }
  }

  func testBlocksAndClosers() throws {
    let tokens = collectTokens("([{}])")
    XCTAssertEqual(tokens.count, 6)
    XCTAssertEqual(tokens[0], .parenthesisBlock)
    XCTAssertEqual(tokens[1], .squareBracketBlock)
    XCTAssertEqual(tokens[2], .curlyBracketBlock)
    XCTAssertEqual(tokens[3], .closeCurlyBracket)
    XCTAssertEqual(tokens[4], .closeSquareBracket)
    XCTAssertEqual(tokens[5], .closeParenthesis)
  }

  func testCDOandCDC() throws {
    XCTAssertEqual(collectTokens("<!--"), [.cdo])
    XCTAssertEqual(collectTokens("-->"), [.cdc])
  }

  func testComment() throws {
    let tokens = collectTokens("/*hello*/")
    XCTAssertEqual(tokens, [.comment("hello")])
  }

  func testDelimitersAndMatches() throws {
    XCTAssertEqual(collectTokens("$="), [.suffixMatch])
    XCTAssertEqual(collectTokens("^="), [.prefixMatch])
    XCTAssertEqual(collectTokens("|="), [.dashMatch])
    XCTAssertEqual(collectTokens("~="), [.includeMatch])
    XCTAssertEqual(collectTokens("+"), [.delim("+")])
    XCTAssertEqual(collectTokens("-"), [.delim("-")])
    XCTAssertEqual(collectTokens("."), [.delim(".")])
    XCTAssertEqual(collectTokens("/"), [.delim("/")])
    XCTAssertEqual(collectTokens(":"), [.colon])
    XCTAssertEqual(collectTokens(";"), [.semicolon])
    XCTAssertEqual(collectTokens("<"), [.delim("<")])
    XCTAssertEqual(collectTokens("@"), [.delim("@")])
    XCTAssertEqual(collectTokens("#"), [.delim("#")])
  }

  func testUnicodeIdent() throws {
    let tokens = collectTokens("色")
    XCTAssertEqual(tokens, [.ident("色")])
  }

  func testFunctionNonUrl() throws {
    let tokens = collectTokens("calc(")
    XCTAssertEqual(tokens, [.function("calc")])
  }

  func testConsumeHexDigitsAndEscape() throws {
    do {
      var tokenizer = Tokenizer(input: "1A2bG")
      let (value, digits) = consumeHexDigits(tokenizer: &tokenizer)
      XCTAssertEqual(value, 0x1A2B)
      XCTAssertEqual(digits, 4)
    }
    do {
      var tokenizer = Tokenizer(input: "41 ")
      let c = consumeEscape(tokenizer: &tokenizer)
      XCTAssertEqual(String(c), "A")
    }
  }
}
