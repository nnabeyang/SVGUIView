import CoreGraphics
import Foundation
import Testing
import _CSSParser

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The computed style of the element with the ID in the content.
private func style(of id: String, in content: String) throws -> ComputedStyle {
  let elements = parse(content).root?.elements ?? []
  return try #require(elements.first { $0.base.id == id }).style
}

/// The red, green and blue from 0 to 255 and the alpha from 0 to 1 of a color, rounded, or `nil` if it isn't one.
private func rgba(of text: String) -> [Double]? {
  let color: SVGColor
  switch Paint(text) {
  case .color(let value)?: color = value
  case .expression(let expression)?: color = expression.resolved(currentColor: .named(SVGColorName(name: "black")))
  default: return nil
  }
  guard let c = color.components else { return nil }
  return [(c.red * 255).rounded(), (c.green * 255).rounded(), (c.blue * 255).rounded(), c.alpha]
}

/// The transform list of a value of `transform`.
private func transform(_ text: String, origin: DeclarationOrigin) -> TransformList? {
  var input = _CSSParser.Parser(input: ParserInput(input: text))
  return TransformList.parse(&input, origin: origin)
}

/// A context for resolving lengths in a viewport of 400 by 400.
private func context() -> ResolveContext {
  let base = SVGParser.parse(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8))
  let viewPort = CGRect(x: 0, y: 0, width: 400, height: 400)
  return ResolveContext(base: base, viewPort: viewPort, scale: 1, viewBox: viewPort)
}

@Suite("Math functions")
struct MathFunctionTests {
  /// Math functions of lengths, and the lengths that they're folded into.
  private static let lengths: [(String, SVGLength)] = [
    ("calc(8 * 5%)", .percent(40)),
    ("calc(1in - 6px)", .pixel(90)),
    ("calc((10px + 5px) * 2)", .pixel(30)),
    ("calc(30px / 3)", .pixel(10)),
    ("CALC(2 * 10px)", .pixel(20)),
    ("calc(10px + calc(5px * 2))", .pixel(20)),
    ("min(180px, 200px)", .pixel(180)),
    ("max(1in, 10px)", .pixel(96)),
    ("clamp(10px, 500px, 180px)", .pixel(180)),
    ("clamp(10px, 5px, 180px)", .pixel(10)),
    ("calc(10em - 5em)", .ems(5)),
    ("calc(80px + 10% - 2em)", SVGLength.sum(of: [.percent(10), .ems(-2), .pixel(80)])!),
  ]

  @Test("math functions of lengths are folded into lengths", arguments: lengths)
  func foldedLengths(text: String, expected: SVGLength) {
    #expect(SVGLength(mathFunction: text) == expected)
  }

  @Test(
    "math functions that aren't valid lengths",
    arguments: [
      "calc(10%+10px)", "calc(10px -5px)", "calc(10px + 5)", "calc(10px * 2px)", "calc(10px / 2px)", "calc(10px +)",
      "calc()", "calc(10px) 5px", "foo(10px)", "calc(10deg)", "min(10px, 5deg)", "clamp(10px, 5px)", "calc(r)",
    ])
  func invalidLengths(text: String) {
    #expect(SVGLength(mathFunction: text) == nil)
  }

  @Test("functions of lengths in units that can't be compared are resolved where they're used")
  func resolvedLengths() throws {
    let context = context()
    let max = try #require(SVGLength(mathFunction: "max(10px, 5%)"))
    guard case .calc = max else {
      Issue.record("max() isn't an expression")
      return
    }
    #expect(max.value(total: 400, context: context) == 20)
    #expect(max.value(total: 100, context: context) == 10)
    let clamp = try #require(SVGLength(mathFunction: "clamp(10px, 50% - 20px, 100px)"))
    #expect(clamp.value(total: 400, context: context) == 100)
    #expect(clamp.value(total: 20, context: context) == 10)
    #expect(clamp.value(total: 100, context: context) == 30)
  }

  @Test("a math function is clamped to the range of a property that isn't negative")
  func nonNegative() throws {
    let context = context()
    #expect(SVGLength(mathFunction: "calc(-10px)", isNonNegative: true) == .pixel(0))
    let length = try #require(SVGLength(mathFunction: "calc(10% - 50px)", isNonNegative: true))
    #expect(length.value(total: 100, context: context) == 0)
    #expect(length.value(total: 1000, context: context) == 50)
  }

  @Test("the geometry properties take math functions in presentation attributes and style sheets")
  func geometry() throws {
    let style = try style(
      of: "e",
      in: #"<rect id="e" x="calc(100px + 100px)" width="calc(90% - 180px)" "#
        + #"style="y: calc(2 * 5%); height: min(20px, 50%)"/>"#)
    #expect(style.x == .pixel(200))
    // The width can't be negative, so it's clamped where it's used.
    #expect(style.width?.value(total: 400, context: context()) == 180)
    #expect(style.width?.value(total: 100, context: context()) == 0)
    #expect(style.y == .percent(10))
    guard case .calc = style.height else {
      Issue.record("min() of lengths in different units isn't an expression")
      return
    }
    #expect(style.height?.value(total: 400, context: context()) == 20)
  }

  @Test("a negative math function of a length that can't be negative isn't invalid, and is 0")
  func negativeGeometry() throws {
    let style = try style(of: "e", in: #"<rect id="e" width="10" height="10" style="width: calc(-10px)"/>"#)
    #expect(style.width == .pixel(0))
  }

  @Test("the position and the size of a nested svg take math functions, as SVG 2 makes them geometry properties")
  func nestedSVG() throws {
    let elements =
      parse(#"<svg id="a" x="calc(10px + 10px)" width="calc(30% + 10px)" height="calc(-1px)"/>"#).root?.elements ?? []
    let a = try #require(elements.first { $0.base.id == "a" } as? SVGSVGElement)
    #expect(a.x == .pixel(20))
    #expect(a.width?.value(total: 400, context: context()) == 130)
    #expect(a.height == .pixel(0))
  }

  @Test("lengths relative to the font in a math function are computed in pixels")
  func fontRelative() throws {
    let style = try style(of: "e", in: #"<rect id="e" font-size="10px" style="x: max(2em, 5%)"/>"#)
    #expect(style.x?.value(total: 1000, context: context()) == 50)
    #expect(style.x?.value(total: 100, context: context()) == 20)
  }

  @Test("other length properties take math functions")
  func otherLengths() throws {
    let style = try style(
      of: "e",
      in: #"<g font-size="10px"><rect id="e" stroke-width="calc(10px * 2)" stroke-dasharray="calc(90px * 2), 0" "#
        + #"stroke-dashoffset="calc(-5px)" letter-spacing="calc(1px + 1px)" style="font-size: calc(1em + 2px)"/></g>"#)
    #expect(style.strokeWidth == .pixel(20))
    #expect(style.strokeDasharray == [.pixel(180), .number(0)])
    #expect(style.strokeDashoffset == .pixel(-5))
    #expect(style.letterSpacing == .pixel(2))
    #expect(style.fontSize == .length(.pixel(12)))
  }

  @Test("number properties take math functions, clamped to their ranges")
  func numbers() throws {
    let style = try style(
      of: "e",
      in: #"<rect id="e" fill-opacity="calc(2 - 2)" stroke-opacity="calc(25% * 2)" stroke-miterlimit="calc(1 / 2)"/>"#)
    #expect(style.fillOpacity == 0)
    #expect(style.strokeOpacity == 0.5)
    #expect(style.strokeMiterlimit == 1)
  }

  @Test("transform functions take math functions in style sheets, and not in attributes")
  func transforms() {
    #expect(
      transform("translate(calc(100px + 100px), min(5%, 5%))", origin: .css)
        == TransformList(functions: [.translate(.pixel(200), .percent(5))]))
    #expect(transform("rotate(calc(0.25turn * 2))", origin: .css) == TransformList(functions: [.rotate(180)]))
    #expect(transform("scale(calc(50% + 50%), calc(2 / 4))", origin: .css) == TransformList(functions: [.scale(1, 0.5)]))
    #expect(transform("translate(calc(100px + 100px) 0)", origin: .attribute) == nil)
    #expect(transform("rotate(calc(10px))", origin: .css) == nil)
  }

  /// Colors with math functions, and their red, green and blue from 0 to 255 and their alpha.
  private static let colors: [(String, [Double])] = [
    ("rgb(calc(0) calc(256 / 2) 0)", [0, 128, 0, 1]),
    ("rgb(calc(50% + 50%) 0 0 / calc(1 / 2))", [255, 0, 0, 0.5]),
    ("rgb(calc(255), 0, 0)", [255, 0, 0, 1]),
    ("hsl(calc(60deg + 0.5turn) 100% 50%)", [0, 0, 255, 1]),
    ("hsl(calc(120) 100% 25%)", [0, 128, 0, 1]),
    ("hsl(from red calc(h + 120) s calc(l / 2))", [0, 128, 0, 1]),
    ("rgb(from red calc(r / 2) g calc(b + 255))", [128, 0, 255, 1]),
    ("rgb(from red r g b / calc(alpha / 2))", [255, 0, 0, 0.5]),
  ]

  @Test("components of colors take math functions, with the components of the origin of a relative color", arguments: colors)
  func colorComponents(text: String, expected: [Double]) {
    let rgba = rgba(of: text)
    let isClose = rgba.map { zip($0, expected).allSatisfy { abs($0 - $1) < 1.01 } } ?? false
    #expect(isClose, "\(text): \(String(describing: rgba))")
  }

  @Test(
    "math functions that aren't valid components of colors",
    arguments: [
      "rgb(calc(10px) 0 0)", "rgb(calc(50% + 10) 0 0)", "hsl(calc(10%) 100% 50%)", "rgb(calc(r) 0 0)",
      "rgb(from red calc(h) g b)", "rgb(calc(1 + ) 0 0)", "rgb(foo(1) 0 0)",
    ])
  func invalidColorComponents(text: String) {
    #expect(rgba(of: text) == nil)
  }

  @Test("a math function of lengths in units that can't be added changes discretely in an animation")
  func interpolation() throws {
    let max = try #require(SVGLength(mathFunction: "max(10px, 5%)"))
    #expect(max.interpolated(to: .pixel(20), progress: 0.5) == nil)
    let sum = try #require(SVGLength(mathFunction: "calc(10px + 5%)"))
    #expect(sum.interpolated(to: .pixel(20), progress: 0.5) == SVGLength.sum(of: [.percent(2.5), .pixel(15)]))
  }
}
