import CoreGraphics
import Foundation
import Testing
import _CSSParser

@testable import SVGCore

private func parse(_ text: String, origin: DeclarationOrigin) -> TransformList? {
  var input = _CSSParser.Parser(input: ParserInput(input: text))
  return TransformList.parse(&input, origin: origin)
}

@Suite("Transform list")
struct TransformListTests {
  /// Transform lists and their functions, in an attribute and in CSS.
  private static let lists: [(DeclarationOrigin, String, [TransformFunction])] = [
    (.attribute, "translate(10,20)", [.translate(.number(10), .number(20))]),
    (.attribute, "translate(10)", [.translate(.number(10), .number(0))]),
    (.attribute, "translate(10px 5%)", [.translate(.pixel(10), .percent(5))]),
    (
      .attribute, "scale(2) , rotate(45 10 20)",
      [.scale(2, 2), .translate(.number(10), .number(20)), .rotate(45), .translate(.number(-10), .number(-20))]
    ),
    (.attribute, "skewX(30)skewY(-10)", [.skew(30, 0), .skew(0, -10)]),
    (.attribute, "rotate(45deg)", [.rotate(45)]),
    (.attribute, "matrix(1 2,3 4 5 6)", [.matrix(CGAffineTransform(a: 1, b: 2, c: 3, d: 4, tx: 5, ty: 6))]),
    (.attribute, "none", []),
    (.attribute, "  matrix  ( 1 0 0 1 2 3 ) translate (4)", [.matrix(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 2, ty: 3)), .translate(.number(4), .number(0))]),
    // The end of the text closes a function, as in CSS.
    (.attribute, "scale(2) translate(10", [.scale(2, 2), .translate(.number(10), .number(0))]),
    (.css, "translateX(1cm) translateY(-2px)", [.translate(.centimeters(1), .number(0)), .translate(.number(0), .pixel(-2))]),
    (.css, "ROTATE(-0.5turn) SkewX(0)", [.rotate(-180), .skew(0, 0)]),
    (.css, "skew(10deg, 20deg) skewY(1deg)", [.skew(10, 20), .skew(0, 1)]),
    (.css, "scale(50%, 2) scaleX(2) scaleY(3)", [.scale(0.5, 2), .scale(2, 1), .scale(1, 3)]),
    (.css, "matrix(1, 2, 3, 4, 5, 6)", [.matrix(CGAffineTransform(a: 1, b: 2, c: 3, d: 4, tx: 5, ty: 6))]),
    (.css, "None", []),
  ]

  @Test("transform functions are read in the basic forms that they're interpolated in", arguments: lists)
  func functions(origin: DeclarationOrigin, text: String, functions: [TransformFunction]) {
    #expect(parse(text, origin: origin) == TransformList(functions: functions))
  }

  /// Transform lists that are invalid, in an attribute and in CSS.
  private static let invalidLists: [(DeclarationOrigin, String)] = [
    (.attribute, ""),
    (.attribute, "Translate(10)"),
    (.attribute, "translate(10) bogus(1)"),
    (.attribute, "translate(10) )"),
    (.attribute, "translate(10) x"),
    (.attribute, "rotate(45 10)"),
    (.attribute, "rotate(1s)"),
    (.attribute, "translate(10deg)"),
    (.attribute, "none translate(10)"),
    (.css, "translate(10, 20)"),
    (.css, "rotate(45)"),
    (.css, "rotate(45deg 10 10)"),
    (.css, "matrix(1 0 0 1 0 0)"),
    (.css, "translate(1px), scale(2)"),
    (.css, "scale(2px)"),
    (.css, "translate (1px)"),
  ]

  @Test("a transform list with a function that isn't valid is invalid", arguments: invalidLists)
  func invalid(origin: DeclarationOrigin, text: String) {
    #expect(parse(text, origin: origin) == nil)
  }

  /// Transform lists of attributes and their matrices, with percentages of a box of 200 by 100.
  private static let matrices: [(String, CGAffineTransform)] = [
    ("translate(10,0) matrix(2,0,0,2,0,0)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 0)),
    ("matrix(2,0,0,2,0,0) translate(10,0)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 20, ty: 0)),
    ("matrix(1 0 0 1 5 0), matrix(0 1 -1 0 0 0)", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 5, ty: 0)),
    ("translate(10, 20) scale(2)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 20)),
    ("scale(2) translate(10 20)", CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 20, ty: 40)),
    ("rotate(90 10 10)", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 20, ty: 0)),
    ("translate(50%, 10%) skewX(45)", CGAffineTransform(a: 1, b: 0, c: 1, d: 1, tx: 100, ty: 10)),
  ]

  @Test("the functions of a transform list apply in the order of the list", arguments: matrices)
  func matrix(text: String, matrix: CGAffineTransform) throws {
    let list = try #require(TransformList(attribute: text))
    let transform = list.matrix(box: CGSize(width: 200, height: 100), context: LengthContextStub())
    let values = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
    let expected = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty]
    #expect(zip(values, expected).allSatisfy { abs($0 - $1) < 1e-9 }, "\(transform)")
  }

  @Test(
    "a transform list written as attribute text is read back as the same list",
    arguments: [
      "translate(10 5%)", "scale(2, 3) rotate(45 10 20)", "skewX(30) skewY(-10)", "matrix(1 2 3 4 5 6)", "none",
      "translateX(2px) scaleY(0.5)",
    ])
  func attributeText(text: String) throws {
    let list = try #require(TransformList(attribute: text))
    #expect(TransformList(attribute: list.attributeText) == list)
  }

  @Test("a skew along both axes is written as a matrix")
  func skewAttributeText() throws {
    let list = TransformList(functions: [.skew(30, 10)])
    let matrix = try #require(TransformList(attribute: list.attributeText))
    let expected = list.matrix(box: .zero, context: LengthContextStub())
    let actual = matrix.matrix(box: .zero, context: LengthContextStub())
    #expect(abs(expected.b - actual.b) < 1e-9 && abs(expected.c - actual.c) < 1e-9)
  }
}

private struct LengthContextStub: SVGLengthContext {
  var viewBoxSize: CGSize { .zero }
  var font: SVGUIFont? { nil }
  var textScale: Double { 1 }
  var rootFont: SVGUIFont? { nil }
  var viewPort: CGRect { .zero }
  var writingMode: WritingMode? { nil }
}
