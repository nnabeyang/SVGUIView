import Foundation

/// The identifier of an element, unique in its document.
///
/// An element keeps its identifier when the document changes elsewhere, so that work done for the element, such as
/// rendering it, can be matched with the element in the next version of the document.
package struct ElementID: Hashable, Sendable {
  package let rawValue: Int
}

/// An element of a parsed document, with its attributes and children as written.
///
/// Elements are immutable and don't know their parents, so a document is a persistent tree: a change makes a new
/// element for each ancestor of the changed element, and shares every other subtree with the previous version.
/// Elements that SVGUIView doesn't render, such as `<style>`, elements in another namespace and unknown elements,
/// stay in the tree, so that selectors see the siblings and ancestors that the document has.
final class DocumentElement: Sendable {
  let id: ElementID
  /// The element's name, or ``SVGElementName/unknown`` for an element that SVGUIView doesn't know or that isn't in
  /// the SVG namespace.
  let name: SVGElementName
  /// The local name as written, which type selectors match.
  let localName: String
  /// The attributes, with the `href` of the XLink namespace as `href` and other prefixed attributes left out.
  let attributes: [String: String]
  /// The text content of `<text>` and `<style>`, and an empty string for other elements.
  let text: String
  let children: [DocumentElement]

  init(
    id: ElementID, name: SVGElementName, localName: String, attributes: [String: String], text: String,
    children: [DocumentElement]
  ) {
    self.id = id
    self.name = name
    self.localName = localName
    self.attributes = attributes
    self.text = text
    self.children = children
  }

  /// The element with its descendant at `path`, a list of child positions from this element, replaced. The elements
  /// on the path are copied with their identifiers, and every other subtree is shared.
  func replacingDescendant(at path: ArraySlice<Int>, with replacement: DocumentElement) -> DocumentElement {
    guard let index = path.first else { return replacement }
    var children = children
    children[index] = children[index].replacingDescendant(at: path.dropFirst(), with: replacement)
    return DocumentElement(
      id: id, name: name, localName: localName, attributes: attributes, text: text, children: children)
  }
}

/// A parsed SVG document.
///
/// A document is a value: background work reads a document, and it stays the same however the document changes
/// later.
struct SVGDocument: Sendable {
  /// The root element, or `nil` for data without an element.
  let root: DocumentElement?

  /// The document with the element at `path`, a list of child positions from the root, replaced.
  func replacingElement(at path: [Int], with replacement: DocumentElement) -> SVGDocument {
    SVGDocument(root: root?.replacingDescendant(at: path[...], with: replacement))
  }
}
