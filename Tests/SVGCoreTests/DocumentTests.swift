import Foundation
import Testing

@testable import SVGCore

/// Makes a document element for a test. Elements that SVGUIView doesn't know become `.unknown`, as the parser
/// makes them.
func documentElement(
  _ id: Int, _ localName: String, _ attributes: [String: String] = [:], _ children: [DocumentElement] = []
) -> DocumentElement {
  DocumentElement(
    id: ElementID(rawValue: id), name: SVGElementName(rawValue: localName) ?? .unknown, localName: localName,
    attributes: attributes, text: "", children: children)
}

@Suite("Document")
struct DocumentTests {
  @Test("replacing an element copies only its ancestors and keeps their identifiers")
  func replacingCopiesPath() throws {
    let document = DocumentTree(
      root: documentElement(
        0, "svg", [:],
        [
          documentElement(1, "g", [:], [documentElement(2, "rect"), documentElement(3, "circle")]),
          documentElement(4, "g", [:], [documentElement(5, "path")]),
        ]), languages: [])
    let replacement = documentElement(3, "circle", ["r": "5"])
    let changed = document.replacingElement(at: [0, 1], with: replacement)

    let root = try #require(document.root)
    let newRoot = try #require(changed.root)
    #expect(newRoot !== root)
    #expect(newRoot.id == root.id)
    #expect(newRoot.children[0] !== root.children[0])
    #expect(newRoot.children[0].id == root.children[0].id)
    #expect(newRoot.children[0].children[1] === replacement)
    // Subtrees off the path are shared.
    #expect(newRoot.children[0].children[0] === root.children[0].children[0])
    #expect(newRoot.children[1] === root.children[1])
    // The previous version doesn't change.
    #expect(root.children[0].children[1].attributes.isEmpty)
  }

  @Test("the document keeps elements that aren't rendered, with their descendants")
  func documentKeepsUnrenderedElements() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://example.com/x" viewBox="0 0 20 20">
        <style>rect { fill: red; }</style>
        <unknown id="s"><rect width="10" height="10"/></unknown>
        <x:foo/>
        <rect width="20" height="20"/>
      </svg>
      """#
    let context = SVGParser.parse(data: Data(svg.utf8))
    let root = try #require(context.document.root)
    #expect(root.children.map(\.localName) == ["style", "unknown", "foo", "rect"])
    #expect(root.children.map(\.name) == [.style, .unknown, .unknown, .rect])
    #expect(root.children[1].children.map(\.localName) == ["rect"])
    #expect(root.children[0].text == "rect { fill: red; }")
    // The unknown elements are made, though they aren't rendered, so that the elements in them can be referenced.
    #expect(context.root?.children.map(\.type) == [.unknown, .unknown, .rect])
  }

  @Test("the text of a text element around its children stays with it")
  func textAroundChildren() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://example.com/x" viewBox="0 0 20 20">
        <text>Hello<x:foo>?</x:foo>!</text>
      </svg>
      """#
    let root = try #require(SVGParser.parse(data: Data(svg.utf8)).document.root)
    #expect(root.children[0].text == "Hello!")
    #expect(root.children[0].texts == ["Hello", "!"])
    #expect(root.children[0].children[0].text == "")
  }

  @Test("text and tspan keep their character data before, between and after their children")
  func textAroundTSpans() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg"><text>a<tspan>b<tspan>c</tspan>d</tspan>e<tspan/>f</text></svg>
      """#
    let root = try #require(SVGParser.parse(data: Data(svg.utf8)).document.root)
    let text = root.children[0]
    #expect(text.texts == ["a", "e", "f"])
    #expect(text.children[0].name == .tspan)
    #expect(text.children[0].texts == ["b", "d"])
    #expect(text.children[0].children[0].texts == ["c"])
    #expect(text.children[1].texts == [""])
  }

  @Test("every element of a document has its own identifier")
  func identifiersAreUnique() throws {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg"><g><rect/><foo/></g><circle/></svg>"#
    let root = try #require(SVGParser.parse(data: Data(svg.utf8)).document.root)
    func identifiers(_ element: DocumentElement) -> [ElementID] {
      [element.id] + element.children.flatMap(identifiers)
    }
    let ids = identifiers(root)
    #expect(ids.count == 5)
    #expect(Set(ids).count == ids.count)
  }

  @Test("a document whose root isn't an svg element in the SVG namespace has nothing to render")
  func rootMustBeSVG() {
    let svg = #"<foo xmlns="http://www.w3.org/2000/svg"><svg><rect width="10" height="10"/></svg></foo>"#
    let context = SVGParser.parse(data: Data(svg.utf8))
    #expect(context.document.root?.localName == "foo")
    #expect(context.root == nil)
  }
}
