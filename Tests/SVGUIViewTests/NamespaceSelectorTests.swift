import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that selectors with namespaces match, with the namespaces that the `@namespace` rules of a style sheet
/// declare, as CSS Namespaces 3 and Selectors 4 have them.
@MainActor
@Suite("Selectors with namespaces")
struct NamespaceSelectorTests {
  private static let xlink = "http://www.w3.org/1999/xlink"
  private static let svg = "http://www.w3.org/2000/svg"

  /// The fill of each element of a document whose style sheet is the CSS, by the identifiers of the elements.
  private func fills(_ css: String, _ content: String) throws -> [String: String] {
    let document = SVGUIView(
      data: Data(
        ##"<svg xmlns="\##(Self.svg)" xmlns:xlink="\##(Self.xlink)"><style>\##(css)</style>\##(content)</svg>"##.utf8)
    ).document
    var fills = [String: String]()
    for element in try document.querySelectorAll("[id]") {
      fills[element.attribute("id") ?? ""] = element.computedStyle.property("fill")
    }
    return fills
  }

  private static let links =
    ##"<use id="x" xlink:href="#r"/><use id="h" href="#r"/><rect id="r" xml:space="preserve"/>"##

  @Test("an attribute selector with a declared prefix matches the attributes in its namespace")
  func prefixedAttribute() throws {
    let found = try fills(
      ##"@namespace xlink url(\##(Self.xlink)); @namespace xml "http://www.w3.org/XML/1998/namespace"; "##
        + "[xlink|href] { fill: lime } [xml|space] { fill: blue }", Self.links)
    #expect(found["x"] == "rgb(0, 255, 0)")
    #expect(found["h"] == "rgb(0, 0, 0)")
    #expect(found["r"] == "rgb(0, 0, 255)")
  }

  @Test("an attribute selector with any namespace matches the attribute in no namespace and in a namespace")
  func anyNamespace() throws {
    let found = try fills("[*|href] { fill: lime } [href] { stroke: red }", Self.links)
    #expect(found["x"] == "rgb(0, 255, 0)")
    #expect(found["h"] == "rgb(0, 255, 0)")
    #expect(found["r"] == "rgb(0, 0, 0)")
    // An attribute selector without a namespace and one with no namespace find the attribute in no namespace only.
    let none = try fills("[|href] { fill: lime }", Self.links)
    #expect(none["x"] == "rgb(0, 0, 0)")
    #expect(none["h"] == "rgb(0, 255, 0)")
  }

  @Test("a type selector with a prefix and the default namespace match the elements in their namespaces")
  func typeSelectors() throws {
    let content = ##"<rect id="r"/><circle id="c"/>"##
    let svg = try fills(
      ##"@namespace s url(\##(Self.svg)); @namespace h url(http://www.w3.org/1999/xhtml); "##
        + "s|rect { fill: lime } h|circle { fill: red }", content)
    #expect(svg["r"] == "rgb(0, 255, 0)")
    #expect(svg["c"] == "rgb(0, 0, 0)")
    let xhtml = try fills("@namespace url(http://www.w3.org/1999/xhtml); rect { fill: red } *|circle { fill: lime }", content)
    #expect(xhtml["r"] == "rgb(0, 0, 0)")
    #expect(xhtml["c"] == "rgb(0, 255, 0)")
  }

  @Test("a prefix that no rule declares drops its rule, and an @namespace rule after a style rule declares nothing")
  func invalidRules() throws {
    let undeclared = try fills("[xlink|href] { fill: red } rect { fill: lime }", Self.links)
    #expect(undeclared["x"] == "rgb(0, 0, 0)")
    #expect(undeclared["r"] == "rgb(0, 255, 0)")
    let late = try fills(
      ##"rect { fill: lime } @namespace xlink url(\##(Self.xlink)); [xlink|href] { fill: red }"##, Self.links)
    #expect(late["x"] == "rgb(0, 0, 0)")
    #expect(late["r"] == "rgb(0, 255, 0)")
  }

  @Test("querySelector finds attributes in any namespace, and throws for a prefix, which it can't declare")
  func querySelector() throws {
    let document = SVGUIView(
      data: Data(##"<svg xmlns="\##(Self.svg)" xmlns:xlink="\##(Self.xlink)">\##(Self.links)</svg>"##.utf8)
    ).document
    #expect(try document.querySelectorAll("[*|href]").map { $0.attribute("id") } == ["x", "h"])
    #expect(throws: SVGDocument.SelectorError.self) { try document.querySelector("[xlink|href]") }
  }
}
