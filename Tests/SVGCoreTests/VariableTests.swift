import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// The document of the content.
private func document(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The computed values of the element with the ID `r` in the content, at a time.
private func computedStyle(_ content: String, at time: Double? = nil) throws -> ComputedStyle {
  let base = document(content)
  return try #require((time.map { base.at(time: $0) } ?? base)["r"]).style
}

@Suite("Custom properties and var()")
struct VariableTests {
  /// Documents and the `stroke-width` of the element `r` in them.
  private static let strokeWidths: [(String, SVGLength)] = [
    // A custom property of a style sheet, and of the `style` attribute.
    (#"<style>rect { --w: 5px }</style><rect id="r" style="stroke-width: var(--w)"/>"#, .pixel(5)),
    (#"<rect id="r" style="--w: 6px; stroke-width: var(--w)"/>"#, .pixel(6)),
    // Custom properties are inherited.
    (#"<g style="--w: 7px"><rect id="r" style="stroke-width: var(--w)"/></g>"#, .pixel(7)),
    // Their names are case-sensitive.
    (#"<g style="--W: 7px; --w: 8px"><rect id="r" style="stroke-width: var(--w)"/></g>"#, .pixel(8)),
    // An important declaration wins over a later one.
    (#"<style>rect { --w: 9px !important }</style><rect id="r" style="--w: 1px; stroke-width: var(--w)"/>"#, .pixel(9)),
    // `initial` takes the value away, and the fallback applies.
    (#"<g style="--w: 7px"><rect id="r" style="--w: initial; stroke-width: var(--w, 3px)"/></g>"#, .pixel(3)),
    (#"<g style="--w: 7px"><g style="--w: 2px"><rect id="r" style="--w: inherit; stroke-width: var(--w)"/></g></g>"#, .pixel(2)),
    // A fallback, and a fallback with `var()` in it.
    (#"<rect id="r" style="stroke-width: var(--missing, 4px)"/>"#, .pixel(4)),
    (#"<rect id="r" style="--b: 5px; stroke-width: var(--missing, var(--b))"/>"#, .pixel(5)),
    // A custom property whose value has `var()`.
    (#"<rect id="r" style="--a: var(--b); --b: 11px; stroke-width: var(--a)"/>"#, .pixel(11)),
    // A value that's invalid after the substitution is `unset`: the inherited value for `stroke-width`.
    (#"<g stroke-width="2"><rect id="r" style="--n: red; stroke-width: var(--n)"/></g>"#, .number(2)),
    // A `var()` with no value and no fallback.
    (#"<g stroke-width="2"><rect id="r" style="stroke-width: var(--missing)"/></g>"#, .number(2)),
    // Custom properties in a cycle have no value, and their fallbacks apply.
    (#"<rect id="r" style="--a: var(--b); --b: var(--a); stroke-width: var(--a, 13px)"/>"#, .pixel(13)),
    (#"<rect id="r" style="--a: var(--a); stroke-width: var(--a, 14px)"/>"#, .pixel(14)),
    // A presentation attribute with `var()` is read as CSS.
    (#"<rect id="r" style="--w: 15px" stroke-width="var(--w)"/>"#, .pixel(15)),
  ]

  @Test("custom properties are substituted for var() when values are computed", arguments: strokeWidths)
  func strokeWidth(content: String, expected: SVGLength) throws {
    #expect(try computedStyle(content).strokeWidth == expected)
  }

  @Test("the attributes of a length with var() are read as CSS, where a number without a unit is invalid")
  func lengthAttributes() throws {
    let css = "<style>rect { --length: 100px; --number: 100 }</style>"
    #expect(try computedStyle(css + #"<rect id="r" width="var(--length)"/>"#).width == .pixel(100))
    #expect(try computedStyle(#"<rect id="r" width="var(--length,100px)"/>"#).width == .pixel(100))
    #expect(try computedStyle(css + #"<rect id="r" width="var(--number)"/>"#).width == WidthProperty.initial)
    #expect(try computedStyle(#"<rect id="r" width="var(--length,100)"/>"#).width == WidthProperty.initial)
    #expect(try computedStyle(#"<rect id="r" width="var(--length)"/>"#).width == WidthProperty.initial)
  }

  @Test("a custom property keeps the text of its value, and the keywords of every property")
  func customValues() throws {
    let style = try computedStyle(#"<rect id="r" style="--a:  rgb( 1 2 3 ) ; --b: ; --c: initial; --d: {a; b}"/>"#)
    #expect(style.customProperties["--a"] == "rgb( 1 2 3 )")
    #expect(style.customProperties["--b"] == "")
    #expect(style.customProperties["--c"] == nil)
    #expect(style.customProperties["--d"] == "{a; b}")
  }

  @Test("var() in a function and in a shorthand is substituted")
  func nestedAndShorthand() throws {
    let style = try computedStyle(
      #"<marker id="m"/><rect id="r" style="--c: 0 128 0; --m: url(#m); fill: rgb(var(--c)); marker: var(--m)"/>"#)
    let expected = try computedStyle(#"<marker id="m"/><rect id="r" style="fill: rgb(0 128 0); marker: url(#m)"/>"#)
    #expect(style.fill == expected.fill)
    #expect(style.markerStart == .url("m"))
    #expect(style.markerEnd == .url("m"))
  }

  @Test("a long chain of var() that grows too long is invalid")
  func substitutionLimit() throws {
    var declarations = "--v0: xxxxxxxxxxxxxxxx;"
    for index in 1...20 {
      declarations += " --v\(index): var(--v\(index - 1)) var(--v\(index - 1));"
    }
    let style = try computedStyle(#"<rect id="r" style="\#(declarations)"/>"#)
    #expect(style.customProperties["--v10"] != nil)
    #expect(style.customProperties["--v20"] == nil)
  }

  @Test("a copy that a use element shows inherits the custom properties of the use element")
  func useInheritance() throws {
    let base = document(
      ##"<defs><rect id="a" style="stroke-width: var(--w)"/></defs><use id="r" href="#a" style="--w: 3px"/>"##)
    let use = try #require(base["r"])
    #expect(use.style.customProperties["--w"] == "3px")
  }

}
