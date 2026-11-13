import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" id="root">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

extension DocumentTree {
  /// The `id` attributes of the children of the element with an `id` attribute.
  fileprivate func childIDs(of id: String) throws -> [String] {
    let element = try #require(element(id: id))
    return children(of: element).map { attributes(of: $0)?["id"] ?? "" }
  }

  /// The element with an `id` attribute, which the document must have.
  fileprivate func require(_ id: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> ElementID {
    try #require(element(id: id), "The document has no element \(id)", sourceLocation: sourceLocation)
  }

  /// Checks that every element is found by its identifier at the position that it has in the tree.
  fileprivate func expectConsistentPositions(sourceLocation: SourceLocation = #_sourceLocation) {
    func visit(_ element: DocumentElement, parent: ElementID?) {
      #expect(cursor(at: element.id)?.element === element, sourceLocation: sourceLocation)
      #expect(self.parent(of: element.id) == parent, sourceLocation: sourceLocation)
      for child in element.children {
        visit(child, parent: element.id)
      }
    }
    if let root { visit(root, parent: nil) }
  }
}

@Suite("Changing the tree of a document")
struct DocumentStructureTests {
  private static let content = """
    <g id="a"><rect id="a1"/><rect id="a2"><title id="t"/></rect><rect id="a3"/></g>\
    <g id="b"><rect id="b1"/></g>
    """

  @Test("an element is inserted among the children of another one, with its descendants", arguments: [0, 1, 3])
  func inserts(index: Int) throws {
    let tree = parse(Self.content).document
    let created = DocumentTree(
      elementNamed: "circle", identifier: try #require(tree.largestElementID) + 1, languages: tree.languages)
    let a = try tree.require("a")
    let inserted = try #require(tree.inserting(created, into: a, at: index))
    var expected = ["a1", "a2", "a3"]
    expected.insert("", at: index)
    #expect(try inserted.childIDs(of: "a") == expected)
    #expect(inserted.localName(of: try #require(created.rootElement)) == "circle")
    inserted.expectConsistentPositions()
    // The document that it's made from stays the same.
    #expect(try tree.childIDs(of: "a") == ["a1", "a2", "a3"])
    tree.expectConsistentPositions()
  }

  @Test("an element can't be inserted in an element that the document doesn't have, or at a position out of range")
  func insertsNothing() throws {
    let tree = parse(Self.content).document
    let created = DocumentTree(elementNamed: "circle", identifier: 100, languages: [])
    let a = try tree.require("a")
    #expect(tree.inserting(created, into: a, at: 4) == nil)
    #expect(tree.inserting(created, into: a, at: -1) == nil)
    #expect(tree.inserting(created, into: try #require(created.rootElement), at: 0) == nil)
  }

  @Test("an element is removed with its descendants, and the later siblings move back", arguments: ["a1", "a2", "a3"])
  func removes(id: String) throws {
    let tree = parse(Self.content).document
    let element = try tree.require(id)
    let (remaining, removed) = try #require(tree.removing(element))
    #expect(try remaining.childIDs(of: "a") == ["a1", "a2", "a3"].filter { $0 != id })
    #expect(!remaining.contains(element))
    #expect(remaining.contains(try tree.require("t")) == (id != "a2"))
    remaining.expectConsistentPositions()
    #expect(removed.rootElement == element)
    #expect(removed.contains(try tree.require("t")) == (id == "a2"))
    removed.expectConsistentPositions()
  }

  @Test("the root, and an element that the document doesn't have, aren't removed")
  func removesNothing() throws {
    let tree = parse(Self.content).document
    #expect(tree.removing(try #require(tree.rootElement)) == nil)
    #expect(tree.removing(ElementID(rawValue: 100)) == nil)
  }

  @Test("a removed element is inserted in another element as the same element")
  func moves() throws {
    let tree = parse(Self.content).document
    let a2 = try tree.require("a2")
    let (remaining, removed) = try #require(tree.removing(a2))
    let moved = try #require(remaining.inserting(removed, into: try tree.require("b"), at: 0))
    #expect(try moved.childIDs(of: "a") == ["a1", "a3"])
    #expect(try moved.childIDs(of: "b") == ["a2", "b1"])
    #expect(moved.element(id: "a2") == a2)
    #expect(moved.parent(of: try tree.require("t")) == a2)
    #expect(moved.isElement(try tree.require("t"), inSubtreeOf: try tree.require("b")))
    #expect(!moved.isElement(try tree.require("b"), inSubtreeOf: a2))
    moved.expectConsistentPositions()
  }

  @Test("the character data around a removed child goes together, and stays before an inserted one")
  func characterData() throws {
    let tree = parse(#"<text id="text">a<tspan id="s">b</tspan>c<tspan id="e">d</tspan>e</text>"#).document
    let text = try tree.require("text")
    let (remaining, removed) = try #require(tree.removing(try tree.require("s")))
    #expect(remaining.cursor(at: text)?.element.texts == ["ac", "e"])
    let inserted = try #require(remaining.inserting(removed, into: text, at: 1))
    #expect(inserted.cursor(at: text)?.element.texts == ["ac", "e", ""])
    #expect(try inserted.childIDs(of: "text") == ["e", "s"])
  }

  @Test("an element that gets a child keeps its other children where the style sheets don't look at the structure")
  func sharesSiblings() throws {
    let base = parse(Self.content)
    let created = DocumentTree(
      elementNamed: "circle", identifier: try #require(base.document.largestElementID) + 1, languages: [])
    let a = try base.document.require("a")
    var changes = DocumentChanges()
    changes.restructured.insert(a)
    changes.inserted.insert(try #require(created.rootElement))
    let changed = base.changing(to: try #require(base.document.inserting(created, into: a, at: 1)), changes: changes)
    func element(_ id: String, in base: SVGBaseContext) -> (any SVGElement)? {
      base.root?.elements.first { $0.base.id == id }
    }
    #expect(element("a", in: changed)?.children.count == 4)
    #expect(element("a", in: changed)?.children[1].base.elementID == created.rootElement)
    for id in ["a1", "a2", "a3", "b", "b1"] {
      #expect(element(id, in: changed) === element(id, in: base), "\(id)")
    }
    #expect(element("a", in: changed) !== element("a", in: base))
  }

  @Test(
    "a pseudo-class of the structure of the tree makes the children of an element that gets a child again",
    arguments: ["rect:nth-child(2) { fill: lime }", "rect:last-child { fill: lime }", "g:empty { fill: lime }"])
  func structuralPseudoClasses(rule: String) throws {
    let base = parse("<style>\(rule)</style>" + Self.content)
    #expect(base.stylesheet.hasStructuralPseudoClasses)
    let created = DocumentTree(
      elementNamed: "circle", identifier: try #require(base.document.largestElementID) + 1, languages: [])
    let a = try base.document.require("a")
    var changes = DocumentChanges()
    changes.restructured.insert(a)
    changes.inserted.insert(try #require(created.rootElement))
    let changed = base.changing(to: try #require(base.document.inserting(created, into: a, at: 0)), changes: changes)
    func element(_ id: String, in base: SVGBaseContext) -> (any SVGElement)? {
      base.root?.elements.first { $0.base.id == id }
    }
    #expect(element("a1", in: changed) !== element("a1", in: base))
    #expect(element("b1", in: changed) === element("b1", in: base))
  }

  @Test("style sheets without pseudo-classes of the structure of the tree", arguments: ["rect + rect { fill: lime }", ".a:not(.b) { fill: lime }", ""])
  func noStructuralPseudoClasses(rule: String) {
    #expect(!parse("<style>\(rule)</style>").stylesheet.hasStructuralPseudoClasses)
  }

  @Test("the children of an element are replaced by character data, and kept as documents of their own")
  func replacesChildren() throws {
    let tree = parse(#"<text id="text">a<tspan id="s">b<tspan id="i">c</tspan></tspan>d<tspan id="e"/></text>"#).document
    #expect(tree.textContent(of: try tree.require("text")) == "abcd")
    #expect(tree.textContent(of: try tree.require("s")) == "bc")
    let text = try tree.require("text")
    let (replaced, removed) = try #require(tree.replacingChildren(of: text, withText: "xyz"))
    #expect(replaced.textContent(of: text) == "xyz")
    #expect(replaced.children(of: text).isEmpty)
    #expect(!replaced.contains(try tree.require("i")))
    replaced.expectConsistentPositions()
    #expect(removed.map(\.rootElement) == [try tree.require("s"), try tree.require("e")])
    #expect(removed[0].textContent(of: try tree.require("s")) == "bc")
    removed[0].expectConsistentPositions()
    // The document that it's made from stays the same.
    #expect(tree.textContent(of: text) == "abcd")
  }

  @Test("the style sheets made from the tree are the ones of the style elements that parsing reads")
  func stylesheetsOfTree() throws {
    let base = parse(
      #"<style>rect { fill: red }</style><g><style type=" Text/CSS ">g { fill: lime }</style></g>"#
        + #"<style type="text/plain">circle { fill: red }</style><style type="">a { fill: blue }</style>"#)
    let sources = StyleSheetSources(document: base.document, processingInstructions: [])
    #expect(sources.sheets.map(\.text) == ["rect { fill: red }", "g { fill: lime }", "a { fill: blue }"])
    #expect(sources.stylesheet.rules.count == base.stylesheet.rules.count)
    #expect(base.document.hasStyleElement)
    #expect(!parse(Self.content).document.hasStyleElement)
  }

  @Test("the style sheets of another context are adopted only when they come from the same style elements")
  func adoptsStyleSheets() {
    let base = parse("<style>@import url(a.css); rect { fill: red }</style>")
    let same = parse(#"<style>@import url(a.css); rect { fill: red }</style><rect/>"#)
    let other = parse("<style>@import url(a.css); rect { fill: blue } g { fill: lime }</style>")
    #expect(base.stylesheet.sources == same.stylesheet.sources)
    #expect(base.stylesheet.sources != other.stylesheet.sources)
    #expect(base.adoptingStyleSheets(of: other, at: 0).stylesheet.rules.count == 1)
  }

  @Test("a change of the style elements makes the style sheets and every element again")
  func changesStylesheets() throws {
    let base = parse(#"<style id="style">rect { fill: red }</style>"# + Self.content)
    let style = try base.document.require("style")
    let (tree, _) = try #require(base.document.replacingChildren(of: style, withText: "g { fill: lime }"))
    var changes = DocumentChanges()
    changes.texts.insert(style)
    changes.stylesheets = true
    let changed = base.changing(to: tree, changes: changes)
    #expect(changed.stylesheet.rules.count == 1)
    for element in base.root?.elements ?? [] {
      #expect(!(changed.root?.elements.contains { $0 === element } ?? false), "\(element.base.id ?? "")")
    }
  }
}
