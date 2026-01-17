import Foundation
import Testing

@testable import _CSSParser

@Suite("Serializer tests")
struct SerializerTests {
  @Test("writeNumeric formats numbers and signs")
  func writeNumeric() {
    do {
      var dest = ""
      _CSSParser.writeNumeric(value: 0.0, intValue: nil, hasSign: true, dest: &dest)
      #expect(dest == "+0")
    }
    do {
      var dest = ""
      _CSSParser.writeNumeric(value: -233333333.54, intValue: nil, hasSign: false, dest: &dest)
      #expect(dest == "-2.333e+08")
    }
    do {
      var dest = ""
      _CSSParser.writeNumeric(value: -233.33333333354, intValue: nil, hasSign: false, dest: &dest)
      #expect(dest == "-233.3")
    }
  }

  @Test("hexEscape emits hex with trailing space")
  func hexEscape() {
    do {
      var dest = ""
      _CSSParser.hexEscape(UInt8(ascii: "f"), dest: &dest)
      #expect(dest == "\\66 ")
    }
    do {
      var dest = ""
      _CSSParser.hexEscape(UInt8(ascii: "0"), dest: &dest)
      #expect(dest == "\\30 ")
    }
  }

  @Test("serializeName escapes spaces")
  func serializeName() {
    var dest = ""
    _CSSParser.serializeName("abc  def", dest: &dest)
    #expect(dest == "abc\\ \\ def")
  }

  @Test("serializeUnquotedUrl escapes spaces")
  func unquotedUrl() {
    var dest = ""
    _CSSParser.serializeUnquotedUrl("images/my bg.jpg", dest: &dest)
    #expect(dest == "images/my\\20 bg.jpg")
  }

  @Test("serializeIdentifier basic and edge cases")
  func serializeIdentifier_BasicAndEdgeCases() {
    do {
      var dest = ""
      serializeIdentifier("abc", dest: &dest)
      #expect(dest == "abc")
    }
    do {
      var dest = ""
      serializeIdentifier("--custom-prop", dest: &dest)
      #expect(dest == "--custom-prop")
    }
    do {
      var dest = ""
      serializeIdentifier("-abc", dest: &dest)
      #expect(dest == "-abc")
    }
    do {
      var dest = ""
      serializeIdentifier("0abc", dest: &dest)
      #expect(dest == "\\30 abc")
    }
    do {
      var dest = ""
      serializeIdentifier("-", dest: &dest)
      #expect(dest == "\\-")
    }
  }

  @Test("serializeName escapes controls and non-name chars")
  func serializeName_EscapesControlsAndNonNameChars() {
    do {
      var dest = ""
      _CSSParser.serializeName("abc  def", dest: &dest)
      #expect(dest == "abc\\ \\ def")
    }
    do {
      var dest = ""
      _CSSParser.serializeName("\u{0007}bell", dest: &dest)
      #expect(dest == "\\7 bell")
    }
    do {
      var dest = ""
      _CSSParser.serializeName("a*b", dest: &dest)
      #expect(dest == "a\\*b")
    }
  }

  @Test("serializeUnquotedUrl escapes spaces and parens")
  func serializeUnquotedUrl_EscapesSpacesAndParens() {
    do {
      var dest = ""
      _CSSParser.serializeUnquotedUrl("images/my bg.jpg", dest: &dest)
      #expect(dest == "images/my\\20 bg.jpg")
    }
    do {
      var dest = ""
      _CSSParser.serializeUnquotedUrl("a(b)c", dest: &dest)
      #expect(dest == "a\\(b\\)c")
    }
  }

  @Test("serializeString quotes and escapes content")
  func serializeString_QuotesAndEscapes() {
    var dest = ""
    _CSSParser.serializeString("a\"b\\c\0d", dest: &dest)
    #expect(dest == "\"a\\\"b\\\\c\u{FFFD}d\"")
  }

  @Test("CssStringWriter writes escaped content only")
  func cssStringWriter_WritesEscapedContentOnly() {
    var inner = ""
    var writer = CssStringWriter(&inner)
    writer.write("a\"b\\c\0d")
    #expect(inner == "a\\\"b\\\\c\u{FFFD}d")
  }

  @Test("Token.toCSSString for simple tokens")
  func tokenToCSS_SimpleTokens() {
    #expect(Token.ident("abc").toCSSString() == "abc")
    #expect(Token.atKeyword("media").toCSSString() == "@media")
    #expect(Token.hash("fff").toCSSString() == "#fff")
    #expect(Token.idHash("id").toCSSString() == "#id")
    #expect(Token.quotedString("hi").toCSSString() == "\"hi\"")
    #expect(Token.unquotedUrl("http://e").toCSSString() == "url(http://e)")
    #expect(Token.delim(":").toCSSString() == ":")
    #expect(Token.colon.toCSSString() == ":")
    #expect(Token.semicolon.toCSSString() == ";")
    #expect(Token.comma.toCSSString() == ",")
    #expect(Token.includeMatch.toCSSString() == "~=")
    #expect(Token.dashMatch.toCSSString() == "|=")
    #expect(Token.prefixMatch.toCSSString() == "^=")
    #expect(Token.suffixMatch.toCSSString() == "$=")
    #expect(Token.substringMatch.toCSSString() == "*=")
    #expect(Token.cdo.toCSSString() == "<!--")
    #expect(Token.cdc.toCSSString() == "-->")
    #expect(Token.function("url").toCSSString() == "url(")
    #expect(Token.parenthesisBlock.toCSSString() == "(")
    #expect(Token.squareBracketBlock.toCSSString() == "[")
    #expect(Token.curlyBracketBlock.toCSSString() == "{")
    #expect(Token.badUrl("oops").toCSSString() == "url(oops)")
    #expect(Token.closeParenthesis.toCSSString() == ")")
    #expect(Token.closeSquareBracket.toCSSString() == "]")
    #expect(Token.closeCurlyBracket.toCSSString() == "}")
  }

  @Test("Token.toCSSString for number/percentage/dimension")
  func tokenToCSS_NumberPercentageDimension() {
    do {
      let n = Token.Number(value: 12.0, intValue: 12, hasSign: false)
      #expect(Token.number(n).toCSSString() == "12")
    }
    do {
      let n = Token.Number(value: 0.0, intValue: 0, hasSign: true)
      #expect(Token.number(n).toCSSString() == "+0")
    }
    do {
      let p = Token.Percentage(unitValue: 0.5, intValue: 50, hasSign: false)
      #expect(Token.percentage(p).toCSSString() == "50%")
    }
    do {
      let d = Token.Dimention(value: 12.0, intValue: 12, hasSign: false, unit: "px")
      #expect(Token.dimention(d).toCSSString() == "12px")
    }
    do {
      let d = Token.Dimention(value: 1.0, intValue: 1, hasSign: false, unit: "e-3")
      #expect(Token.dimention(d).toCSSString() == "1\\65 -3")
    }
  }

  @Test("Bad string adds opening quote and escapes")
  func tokenToCSS_BadStringAddsOpeningQuoteAndEscapes() {
    let t = Token.badString("a\"b")
    #expect(t.toCSSString() == "\"a\\\"b")
  }
}
