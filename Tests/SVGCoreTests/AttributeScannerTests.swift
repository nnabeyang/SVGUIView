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
    #expect(TransformList(attribute: text) == nil)
  }

  /// Values of `url()` and the IDs that they reference, or `nil` for a value that isn't valid. The whitespace around
  /// the URL is removed, also in quotes, as SVG 2 processes URLs.
  private static let urls: [(String, String?)] = [
    ("url(#a)", "a"),
    ("url( #a )", "a"),
    (##"url("#a")"##, "a"),
    ("url('#a')", "a"),
    ("url(' #a ')", "a"),
    (##"url( " #a" )"##, "a"),
    ("url('#a b')", "a b"),
    ("url(' # a ')", " a"),
    ("url('#a)", nil),
    ("url(a)", nil),
    ("url('#')", nil),
  ]

  @Test("url() references an ID in quotes or not, without the whitespace around it", arguments: urls)
  func urlReferences(text: String, id: String?) {
    #expect(Paint(text) == id.map { .url($0, fallback: nil) })
    #expect(Paint(text + " red") == id.map { .url($0, fallback: .color(.named(SVGColorName(name: "red")))) })
    #expect(SVGClipPath(description: text) == id.map { .url(url: $0) })
    #expect(SVGMask(description: text) == id.map { .url(url: $0) })
    #expect(SVGMarkerReference(description: text) == id.map { .url($0) })
    #expect(SVGFilter(description: text) == id.map { .list([.url($0)]) })
  }

  /// `font-family` values and their families.
  private static let familyTexts: [(String, [String])] = [
    ("a, b", ["a", "b"]),
    (#""a b", c"#, ["a b", "c"]),
    ("'Arial", ["Arial"]),
    ("a,,b", []),
    ("(", []),
    ("Hoefler Text", ["Hoefler Text"]),
    ("Times  New   Roman, serif", ["Times New Roman", "-webkit-serif"]),
    (#""a b" c"#, []),
    ("serif foo", ["serif foo"]),
    ("'serif', a", ["serif", "a"]),
  ]

  @Test(
    "font families are sequences of names or strings, and a string without the closing quote ends at the end",
    arguments: familyTexts)
  func fontFamilies(text: String, families: [String]) {
    #expect(SVGUIFont(name: text, size: .medium, weight: .normal).families == families)
  }

  @Test(
    "viewBox reads four numbers separated by whitespace or a comma with optional whitespace",
    arguments: ["0 0 620 340", "0,0,620,340", "0, 0, 620, 340", "0 0,620 340", " 0 0 620 340 "])
  func viewBox(text: String) throws {
    let rect = try #require(SVGSVGElement.parseViewBox(text))
    #expect(rect.toCGRect() == CGRect(x: 0, y: 0, width: 620, height: 340))
  }

  @Test("viewBox isn't read from a list that isn't four numbers", arguments: ["0,,0,1,1", "0 0 1", ",0 0 1 1", "0 0 1 1,", "0 0 1 1 1"])
  func invalidViewBox(text: String) {
    #expect(SVGSVGElement.parseViewBox(text) == nil)
  }
}
