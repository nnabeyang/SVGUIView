import Foundation
import Testing

@testable import SVGUIView

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
    let document = SVGDocument(
      root: documentElement(
        0, "svg", [:],
        [
          documentElement(1, "g", [:], [documentElement(2, "rect"), documentElement(3, "circle")]),
          documentElement(4, "g", [:], [documentElement(5, "path")]),
        ]))
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

}
