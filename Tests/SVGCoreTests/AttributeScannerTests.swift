import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

@Suite("Attribute scanner")
struct AttributeScannerTests {
  /// Values that aren't valid for any of the attributes that the scanner reads.
  private static let invalidTexts = ["(", ")", "url(#)", "url(", ",", " ", "1"]

  @Test("values that aren't valid are ignored without crashing", arguments: invalidTexts)
  func invalidValues(text: String) {
    #expect(Paint(text) == nil)
    #expect(ColorValue(text) == nil)
    #expect(SVGClipPath(description: text) == nil)
    #expect(SVGMask(description: text) == nil)
    #expect(SVGFilter(description: text) == nil)
    #expect(PreserveAspectRatio(description: text) == nil)
    #expect(CGAffineTransform(description: text) == nil)
  }

  /// `font-family` values and their families.
  private static let familyTexts: [(String, [String])] = [
    ("a, b", ["a", "b"]),
    (#""a b", c"#, ["a b", "c"]),
    ("'Arial", ["Arial"]),
    ("a,,b", []),
    ("(", []),
  ]

  @Test(
    "font families are names or strings, and a string without the closing quote ends at the end",
    arguments: familyTexts)
  func fontFamilies(text: String, families: [String]) {
    #expect(SVGUIFont(name: text, size: .medium, weight: .normal).families == families)
  }
}
