import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// The document of the content.
private func document(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The computed values of the element with the ID `r` in the content.
private func computedStyle(_ content: String) throws -> ComputedStyle {
  try #require(document(content)["r"]).style
}

@Suite("Reading lengths")
struct LengthParsingTests {
  @Test(
    "a length with white space between its number and its unit, or with characters after its unit, is invalid",
    arguments: ["1 px", "1\tpx", "1px x", "1pxx", "1px)", "1 %", "1 e2px", "calc(1px) x", "px", ""])
  func invalidLengths(text: String) {
    #expect(SVGLength(text) == nil)
    #expect(SVGLength(property: text) == nil)
  }

  @Test(
    "a length with white space around it is valid",
    arguments: [
      (" 1px ", SVGLength.pixel(1)), ("1", .number(1)), ("1e2px", .pixel(100)), ("\t2%\t", .percent(2)),
    ])
  func validLengths(text: String, expected: SVGLength) {
    #expect(SVGLength(text) == expected)
    #expect(SVGLength(property: text) == expected)
  }

  @Test(
    "a declaration of a length with white space or a comment between its number and its unit is invalid",
    arguments: [
      #"<rect id="r" style="stroke-width: 1 px"/>"#,
      #"<style>rect { stroke-width: 1/**/px }</style><rect id="r"/>"#,
      #"<rect id="r" style="stroke-width: 1/**/px"/>"#,
      #"<rect id="r" style="--n: 1; stroke-width: var(--n)px"/>"#,
      #"<style>rect { --n: 1 }</style><rect id="r" style="stroke-width: var(--n)px"/>"#,
      #"<rect id="r" style="stroke-width: var(--missing, 1)px"/>"#,
      #"<rect id="r" style="--n: 1; --u: px; stroke-width: var(--n)var(--u)"/>"#,
      #"<rect id="r" style="--n: 1; stroke-width: var(--n)/**/px"/>"#,
      #"<rect id="r" style="--n: 1" stroke-width="var(--n)px"/>"#,
      #"<rect id="r" stroke-width="1 px"/>"#,
      #"<rect id="r" stroke-width="1px x"/>"#,
    ])
  func invalidStrokeWidths(content: String) throws {
    #expect(try computedStyle(#"<g stroke-width="3">"# + content + "</g>").strokeWidth == .number(3))
  }

  @Test(
    "a geometry property with white space between its number and its unit is invalid",
    arguments: [
      #"<rect id="r" width="1 px"/>"#,
      #"<rect id="r" style="width: 1 px"/>"#,
      #"<style>rect { width: 1/**/px }</style><rect id="r"/>"#,
      #"<rect id="r" style="--n: 1; width: var(--n)px"/>"#,
      #"<rect id="r" width="1px x"/>"#,
    ])
  func invalidWidths(content: String) throws {
    #expect(try computedStyle(content).width == WidthProperty.initial)
  }

  @Test("var() next to a unit with white space or a comment between them is a length where the unit is in the value")
  func variablesWithUnits() throws {
    #expect(try computedStyle(#"<rect id="r" style="--n: 1px; stroke-width: var(--n)"/>"#).strokeWidth == .pixel(1))
    #expect(try computedStyle(#"<rect id="r" style="--n: 2; stroke-width: calc(var(--n) * 1px)"/>"#).strokeWidth == .pixel(2))
  }

  @Test("a list with a number and a unit apart is invalid")
  func invalidLists() throws {
    #expect(try computedStyle(#"<rect id="r" stroke-dasharray="1 px"/>"#).strokeDasharray == [])
    let text = try #require(document(#"<text id="r" x="1 px">a</text>"#)["r"] as? SVGTextElement)
    #expect(text.positions.x == [])
  }
}
