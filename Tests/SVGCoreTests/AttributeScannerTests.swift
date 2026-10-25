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

extension AttributeScannerTests {
  /// Transform lists and their matrices.
  private static let transformTexts: [(String, CGAffineTransform)] = [
    ("translate(10,0) matrix(2,0,0,2,0,0)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 0)),
    ("matrix(2,0,0,2,0,0) translate(10,0)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 20, ty: 0)),
    ("matrix(1 0 0 1 5 0), matrix(0 1 -1 0 0 0)", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 5, ty: 0)),
    ("translate(10, 20) scale(2)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 20)),
    ("scale(2) translate(10 20)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 20, ty: 40)),
    ("rotate(90 10 10)", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 20, ty: 0)),
  ]

  @Test("the functions of a transform list apply in the order of the list", arguments: transformTexts)
  func transformOrder(text: String, matrix: CGAffineTransform) throws {
    let transform = try #require(CGAffineTransform(description: text))
    let values = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
    let expected = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty]
    #expect(zip(values, expected).allSatisfy { abs($0 - $1) < 1e-9 }, "\(transform)")
  }
}

extension AttributeScannerTests {
  private static let invalidTransformTexts = [
    "translate(10) bogus(1)", "translate(10) )", "scale(2) translate(10", "translate(10) x", "rotate(45deg)",
  ]

  @Test("a transform list with a function that isn't valid is ignored", arguments: invalidTransformTexts)
  func invalidTransformLists(text: String) {
    #expect(CGAffineTransform(description: text) == nil)
  }
}
