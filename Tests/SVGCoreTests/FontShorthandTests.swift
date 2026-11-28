import Foundation
import Testing

@testable import SVGCore

/// The computed style of the element `r` of text in a group with a font of its own, whose `style` attribute is the
/// declarations.
private func textStyle(_ declarations: String) throws -> ComputedStyle {
  let svg =
    #"<svg xmlns="http://www.w3.org/2000/svg"><g font-family="fantasy" font-size="7px" font-weight="300" font-style="italic">"#
    + #"<text id="r" style="\#(declarations)">a</text></g></svg>"#
  return try #require(SVGParser.parse(data: Data(svg.utf8))["r"]).style
}

/// The style, the weight, the size and the family of the font of a style.
private func font(_ style: ComputedStyle) -> [String] {
  ["\(style.fontStyle)", "\(style.fontWeight)", "\(style.fontSize)", style.fontFamily]
}

@Suite("The shorthand font")
struct FontShorthandTests {
  /// Values of `font`, and the longhands that give the same font, or `nil` for a value that isn't valid, which
  /// leaves the font of the group. The values are the ones that Chrome and Firefox agree on.
  private static let values: [(String, String?)] = [
    ("italic bold 30px serif", "font-style: italic; font-weight: bold; font-size: 30px; font-family: serif"),
    ("700 30px/2 serif", "font-style: normal; font-weight: 700; font-size: 30px; font-family: serif"),
    ("small-caps condensed 30px serif", "font-style: normal; font-weight: normal; font-size: 30px; font-family: serif"),
    ("oblique 10deg 30px serif", "font-style: oblique 10deg; font-weight: normal; font-size: 30px; font-family: serif"),
    ("bold OBLIQUE 30PX Serif", "font-style: oblique; font-weight: bold; font-size: 30px; font-family: Serif"),
    ("normal normal 30px serif", "font-style: normal; font-weight: normal; font-size: 30px; font-family: serif"),
    ("normal normal normal normal 30px serif", "font-style: normal; font-weight: normal; font-size: 30px; font-family: serif"),
    (
      "30px Times New Roman, 'Helvetica Neue', sans-serif",
      "font-style: normal; font-weight: normal; font-size: 30px; font-family: Times New Roman, 'Helvetica Neue', sans-serif"
    ),
    ("xxx-large serif", "font-style: normal; font-weight: normal; font-size: xxx-large; font-family: serif"),
    ("0 serif", "font-style: normal; font-weight: normal; font-size: 0; font-family: serif"),
    ("30px/normal 'A B'", "font-style: normal; font-weight: normal; font-size: 30px; font-family: 'A B'"),
    ("lighter calc(10px + 20px) serif", "font-style: normal; font-weight: lighter; font-size: 30px; font-family: serif"),
    ("caption", "font-style: normal; font-weight: normal; font-size: medium; font-family: system-ui"),
    ("30px", nil),
    ("bold serif", nil),
    ("30px 20px", nil),
    ("bold italic bold 30px serif", nil),
    ("30px serif inherit", nil),
    ("normal normal normal normal normal 30px serif", nil),
    ("oblique 100deg 30px serif", nil),
    ("30px/ serif", nil),
    ("30px 'A' B", nil),
    ("caption serif", nil),
  ]

  @Test(
    "font sets the style, the weight, the size and the family, and is invalid without a size or a family",
    arguments: values)
  func value(text: String, longhands: String?) throws {
    let style = try textStyle("font: \(text)")
    let expected = try textStyle(longhands ?? "")
    #expect(font(style) == font(expected))
  }

  @Test("font sets the longhands that it doesn't give to their initial values")
  func resetsLonghands() throws {
    let style = try textStyle("font-style: italic; font-weight: bold; font: 30px serif")
    #expect(style.fontStyle == .normal)
    #expect(style.fontWeight == .normal)
    // A longhand after the shorthand wins.
    #expect(try textStyle("font: 30px serif; font-weight: bold").fontWeight == .bold)
  }

  @Test("font takes the keywords that every property takes, and var()")
  func keywordsAndVariables() throws {
    let inherited = try textStyle("font: inherit")
    #expect(font(inherited) == font(try textStyle("")))
    let variable = try textStyle("--f: bold 30px; font: var(--f) serif")
    #expect(font(variable) == font(try textStyle("font: bold 30px serif")))
  }

  @Test("font isn't an attribute")
  func attribute() throws {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg"><text id="r" font="italic bold 30px serif">a</text></svg>"#
    let style = try #require(SVGParser.parse(data: Data(svg.utf8))["r"]).style
    #expect(style.fontStyle == .normal)
    #expect(style.fontWeight == .normal)
  }
}
