import Foundation
import XCTest

@testable import _CSSParser

final class SerializerTests: XCTestCase {
  func testWriteNumeric() {
    do {
      var dest = ""
      writeNumeric(value: 0.0, intValue: nil, hasSign: true, dest: &dest)
      XCTAssertEqual(dest, "+0")
    }
    do {
      var dest = ""
      writeNumeric(value: -233333333.54, intValue: nil, hasSign: false, dest: &dest)
      XCTAssertEqual(dest, "-2.333e+08")
    }
    do {
      var dest = ""
      writeNumeric(value: -233.33333333354, intValue: nil, hasSign: false, dest: &dest)
      XCTAssertEqual(dest, "-233.3")
    }
  }

  func testHexEscape() {
    do {
      var dest = ""
      hexEscape(UInt8(ascii: "f"), dest: &dest)
      XCTAssertEqual(dest, "\\66 ")
    }
    do {
      var dest = ""
      hexEscape(UInt8(ascii: "0"), dest: &dest)
      XCTAssertEqual(dest, "\\30 ")
    }
  }

  func testSerializeName() {
    var dest = ""
    serializeName("abc  def", dest: &dest)
    XCTAssertEqual(dest, "abc\\ \\ def")
  }

  func testUnquotedUrl() {
    var dest = ""
    serializeUnquotedUrl("images/my bg.jpg", dest: &dest)
    XCTAssertEqual(dest, "images/my\\20 bg.jpg")
  }

  func testSerializeIdentifier_BasicAndEdgeCases() {
    do {
      var dest = ""
      serializeIdentifier("abc", dest: &dest)
      XCTAssertEqual(dest, "abc")
    }
    do {
      var dest = ""
      serializeIdentifier("--custom-prop", dest: &dest)
      XCTAssertEqual(dest, "--custom-prop")
    }
    do {
      var dest = ""
      serializeIdentifier("-abc", dest: &dest)
      XCTAssertEqual(dest, "-abc")
    }
    do {
      var dest = ""
      serializeIdentifier("0abc", dest: &dest)
      XCTAssertEqual(dest, "\\30 abc")
    }
    do {
      var dest = ""
      serializeIdentifier("-", dest: &dest)
      XCTAssertEqual(dest, "\\-")
    }
  }

  func testSerializeName_EscapesControlsAndNonNameChars() {
    do {
      var dest = ""
      serializeName("abc  def", dest: &dest)
      XCTAssertEqual(dest, "abc\\ \\ def")
    }
    do {
      var dest = ""
      serializeName("\u{0007}bell", dest: &dest)
      XCTAssertEqual(dest, "\\7 bell")
    }
    do {
      var dest = ""
      serializeName("a*b", dest: &dest)
      XCTAssertEqual(dest, "a\\*b")
    }
  }

  func testSerializeUnquotedUrl_EscapesSpacesAndParens() {
    do {
      var dest = ""
      serializeUnquotedUrl("images/my bg.jpg", dest: &dest)
      XCTAssertEqual(dest, "images/my\\20 bg.jpg")
    }
    do {
      var dest = ""
      serializeUnquotedUrl("a(b)c", dest: &dest)
      XCTAssertEqual(dest, "a\\(b\\)c")
    }
  }

  func testSerializeString_QuotesAndEscapes() {
    var dest = ""
    serializeString("a\"b\\c\0d", dest: &dest)
    XCTAssertEqual(dest, "\"a\\\"b\\\\c\u{FFFD}d\"")
  }

  func testCssStringWriter_WritesEscapedContentOnly() {
    var inner = ""
    var writer = CssStringWriter(&inner)
    writer.write("a\"b\\c\0d")
    XCTAssertEqual(inner, "a\\\"b\\\\c\u{FFFD}d")
  }

  func testTokenToCSS_SimpleTokens() {
    XCTAssertEqual(Token.ident("abc").toCSSString(), "abc")
    XCTAssertEqual(Token.atKeyword("media").toCSSString(), "@media")
    XCTAssertEqual(Token.hash("fff").toCSSString(), "#fff")
    XCTAssertEqual(Token.idHash("id").toCSSString(), "#id")
    XCTAssertEqual(Token.quotedString("hi").toCSSString(), "\"hi\"")
    XCTAssertEqual(Token.unquotedUrl("http://e").toCSSString(), "url(http://e)")
    XCTAssertEqual(Token.delim(":").toCSSString(), ":")
    XCTAssertEqual(Token.colon.toCSSString(), ":")
    XCTAssertEqual(Token.semicolon.toCSSString(), ";")
    XCTAssertEqual(Token.comma.toCSSString(), ",")
    XCTAssertEqual(Token.includeMatch.toCSSString(), "~=")
    XCTAssertEqual(Token.dashMatch.toCSSString(), "|=")
    XCTAssertEqual(Token.prefixMatch.toCSSString(), "^=")
    XCTAssertEqual(Token.suffixMatch.toCSSString(), "$=")
    XCTAssertEqual(Token.substringMatch.toCSSString(), "*=")
    XCTAssertEqual(Token.cdo.toCSSString(), "<!--")
    XCTAssertEqual(Token.cdc.toCSSString(), "-->")
    XCTAssertEqual(Token.function("url").toCSSString(), "url(")
    XCTAssertEqual(Token.parenthesisBlock.toCSSString(), "(")
    XCTAssertEqual(Token.squareBracketBlock.toCSSString(), "[")
    XCTAssertEqual(Token.curlyBracketBlock.toCSSString(), "{")
    XCTAssertEqual(Token.badUrl("oops").toCSSString(), "url(oops)")
    XCTAssertEqual(Token.closeParenthesis.toCSSString(), ")")
    XCTAssertEqual(Token.closeSquareBracket.toCSSString(), "]")
    XCTAssertEqual(Token.closeCurlyBracket.toCSSString(), "}")
  }

  func testTokenToCSS_NumberPercentageDimension() {
    do {
      let n = Token.Number(value: 12.0, intValue: 12, hasSign: false)
      XCTAssertEqual(Token.number(n).toCSSString(), "12")
    }
    do {
      let n = Token.Number(value: 0.0, intValue: 0, hasSign: true)
      XCTAssertEqual(Token.number(n).toCSSString(), "+0")
    }
    do {
      let p = Token.Percentage(unitValue: 0.5, intValue: 50, hasSign: false)
      XCTAssertEqual(Token.percentage(p).toCSSString(), "50%")
    }
    do {
      let d = Token.Dimention(value: 12.0, intValue: 12, hasSign: false, unit: "px")
      XCTAssertEqual(Token.dimention(d).toCSSString(), "12px")
    }
    do {
      let d = Token.Dimention(value: 1.0, intValue: 1, hasSign: false, unit: "e-3")
      XCTAssertEqual(Token.dimention(d).toCSSString(), "1\\65 -3")
    }
  }

  func testTokenToCSS_BadStringAddsOpeningQuoteAndEscapes() {
    let t = Token.badString("a\"b")
    XCTAssertEqual(t.toCSSString(), "\"a\\\"b")
  }
}
