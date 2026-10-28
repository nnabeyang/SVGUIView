import Foundation
import Testing

@testable import SVGCore

/// The document that the tests search:
///
/// ```
/// <svg id="root">
///   <style id="s"/>
///   <g id="g" class="a">
///     <rect id="r1" x="1"/>
///     <foo id="f"/>
///     <g id="inner"><rect id="r2"/></g>
///   </g>
///   <rect id="r3" class="a"/>
///   <circle id="r1"/>
/// </svg>
/// ```
private let document = SVGParser.parse(
  data: Data(
    #"""
    <svg xmlns="http://www.w3.org/2000/svg" id="root">
      <style id="s"></style>
      <g id="g" class="a">
        <rect id="r1" x="1"/>
        <foo id="f"/>
        <g id="inner"><rect id="r2"/></g>
      </g>
      <rect id="r3" class="a"/>
      <circle id="r1"/>
    </svg>
    """#.utf8)
).document

/// The IDs of elements as their `id` attributes.
private func ids(_ elements: [ElementID]) -> [String] {
  elements.map { document.attributes(of: $0)?["id"] ?? "?" }
}

@Suite("Finding the elements of a document")
struct DocumentQueryTests {
  @Test("an ID finds the first element with it, including elements that SVGUIView doesn't render")
  func elementByID() throws {
    let first = try #require(document.element(id: "r1"))
    #expect(document.cursor(at: first)?.element.localName == "rect")
    #expect(ids([try #require(document.element(id: "s"))]) == ["s"])
    #expect(ids([try #require(document.element(id: "f"))]) == ["f"])
    #expect(ids([try #require(document.element(id: "root"))]) == ["root"])
    #expect(document.element(id: "none") == nil)
  }

  @Test(
    "selectors find the elements that they match in document order",
    arguments: [
      ("rect", ["r1", "r2", "r3"]), (".a", ["g", "r3"]), ("rect, .a", ["g", "r1", "r2", "r3"]),
      ("g rect", ["r1", "r2"]), ("svg > rect", ["r3"]), ("foo", ["f"]), (#"[x="1"]"#, ["r1"]),
      (":root", ["root"]), ("g > :nth-child(2)", ["f"]), ("rect:hover", []),
    ])
  func selectors(css: String, expected: [String]) throws {
    #expect(ids(try document.elements(matching: css)) == expected)
  }

  @Test(
    "selectors from an element find its descendants that they match against the whole document",
    arguments: [
      ("rect", ["r1", "r2"]), ("g", ["inner"]), ("svg g rect", ["r1", "r2"]), (".a rect", ["r1", "r2"]),
      ("circle", []),
    ])
  func selectorsInElement(css: String, expected: [String]) throws {
    let g = try #require(document.element(id: "g"))
    #expect(ids(try document.elements(matching: css, in: g)) == expected)
  }

  @Test("selectors that can't be parsed throw", arguments: ["", "rect {", "rect,", "#", "rect >"])
  func invalidSelectors(css: String) {
    #expect(throws: SelectorSyntaxError(selectors: css)) {
      try document.elements(matching: css)
    }
  }

  @Test("a selector whose brackets aren't closed at the end is closed, as CSS parses it")
  func unclosedBrackets() throws {
    #expect(ids(try document.elements(matching: "[x")) == ["r1"])
  }

  @Test("the root element, and the local names of elements as written")
  func names() throws {
    let root = try #require(document.rootElement)
    #expect(document.localName(of: root) == "svg")
    #expect(document.localName(of: try #require(document.element(id: "f"))) == "foo")
    #expect(DocumentTree(root: nil).rootElement == nil)
  }

  @Test("an element that the document doesn't have has no attributes and no descendants")
  func missingElement() throws {
    let missing = ElementID(rawValue: 1000)
    #expect(document.attributes(of: missing) == nil)
    #expect(document.localName(of: missing) == nil)
    #expect(try document.elements(matching: "rect", in: missing).isEmpty)
  }
}
