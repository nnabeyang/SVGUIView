import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

@Suite("Filter values")
struct FilterValueTests {
  /// Values of `filter`, and what they are.
  private static let values: [(String, SVGFilter)] = [
    ("none", .none),
    ("url(#a)", .list([.url("a")])),
    (##"url("#a") url(#b)"##, .list([.url("a"), .url("b")])),
    ("blur()", .list([.blur(.number(0))])),
    ("blur(4)", .list([.blur(.number(4))])),
    ("blur(1mm)", .list([.blur(.millimeters(1))])),
    (
      "drop-shadow(blue 4 5 6)",
      .list([.dropShadow(color: ColorValue("blue")!, dx: .number(4), dy: .number(5), deviation: .number(6))])
    ),
    (
      "drop-shadow(4 5 rgb(0, 0, 255))",
      .list([.dropShadow(color: ColorValue("rgb(0, 0, 255)")!, dx: .number(4), dy: .number(5), deviation: .number(0))])
    ),
    (
      "drop-shadow(10 15)",
      .list([.dropShadow(color: .currentColor, dx: .number(10), dy: .number(15), deviation: .number(0))])
    ),
    ("grayscale()", .list([.colorAdjust(.grayscale, 1)])),
    ("grayscale(50%) opacity(2)", .list([.colorAdjust(.grayscale, 0.5), .colorAdjust(.opacity, 1)])),
    ("brightness(2)", .list([.colorAdjust(.brightness, 2)])),
    ("hue-rotate()", .list([.hueRotate(0)])),
    ("hue-rotate(0.5turn)", .list([.hueRotate(180)])),
    ("hue-rotate(100grad)", .list([.hueRotate(90)])),
  ]

  @Test("a filter value is none or a list of references and filter functions", arguments: values)
  func value(text: String, expected: SVGFilter) {
    #expect(SVGFilter(description: text) == expected)
  }

  /// Values that aren't valid, with an item that isn't valid, which makes the whole value invalid.
  private static let invalidValues = [
    "", "url()", "url(#)", "blur(4 2)", "blur(50%)", "blur(-5)", "drop-shadow()", "drop-shadow(4)",
    "drop-shadow(red, 10, 15)", "drop-shadow(blue 4 5 6 7)", "drop-shadow(blue 3% 4% 5%)", "drop-shadow(1 2 -3)",
    "hue-rotate(random)", "grayscale(-1)", "grayscale() hue-rotate(random) opacity(0.5)", "blur(4)blur(4)",
    "unknown(1)", "none blur(4)",
  ]

  @Test("a value with an item that isn't valid isn't valid", arguments: invalidValues)
  func invalidValue(text: String) {
    #expect(SVGFilter(description: text) == nil)
  }

  @Test("the references of a filter value are the IDs of its url() items")
  func references() {
    #expect(SVGFilter(description: "url(#a) blur(2) url(#b)")?.references == ["a", "b"])
    #expect(SVGFilter.none.references.isEmpty)
  }
}
