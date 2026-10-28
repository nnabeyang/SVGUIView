import Foundation
import _SelectorParser

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
package struct DocumentTree: Sendable {
  /// The root element, or `nil` for data without an element.
  let root: DocumentElement?
  /// The positions of the elements, as lists of child positions from the root. Changes to attributes keep them.
  private let paths: [ElementID: [Int]]

  init(root: DocumentElement?) {
    var paths = [ElementID: [Int]]()
    func visit(_ element: DocumentElement, path: [Int]) {
      paths[element.id] = path
      for (index, child) in element.children.enumerated() {
        visit(child, path: path + [index])
      }
    }
    if let root {
      visit(root, path: [])
    }
    self.init(root: root, paths: paths)
  }

  private init(root: DocumentElement?, paths: [ElementID: [Int]]) {
    self.root = root
    self.paths = paths
  }

  /// The document with the given attributes of its elements replaced.
  ///
  /// - Parameter replacements: The attributes to set by the elements that they're set on.
  func replacingAttributes(_ replacements: [ElementID: [String: String]]) -> DocumentTree {
    changingAttributes(replacements.mapValues { $0.mapValues { Optional($0) } })
  }

  /// The document with attributes of its elements set or removed. The elements that change, and their ancestors,
  /// are copied with their identifiers, and every other subtree is shared.
  ///
  /// - Parameter changes: The values to set by the elements and the names of the attributes, with `nil` to remove an
  ///   attribute.
  package func changingAttributes(_ changes: [ElementID: [String: String?]]) -> DocumentTree {
    guard var root, !changes.isEmpty else { return self }
    for (id, values) in changes {
      guard let path = paths[id] else { continue }
      let element = path.reduce(root) { $0.children[$1] }
      var attributes = element.attributes
      for (name, value) in values {
        attributes[name] = value
      }
      root = root.replacingDescendant(
        at: path[...],
        with: DocumentElement(
          id: id, name: element.name, localName: element.localName, attributes: attributes, text: element.text,
          children: element.children))
    }
    return DocumentTree(root: root, paths: paths)
  }

  /// The document with the element at `path`, a list of child positions from the root, replaced.
  func replacingElement(at path: [Int], with replacement: DocumentElement) -> DocumentTree {
    DocumentTree(root: root?.replacingDescendant(at: path[...], with: replacement))
  }

  // MARK: - Finding elements

  /// The cursor at an element, or `nil` if the document has no such element.
  func cursor(at id: ElementID) -> ElementCursor? {
    guard let root, let path = paths[id] else { return nil }
    return path.reduce(ElementCursor(root: root)) { $0.child(at: $1) }
  }

  /// The root element, or `nil` for data without an element.
  package var rootElement: ElementID? {
    root?.id
  }

  /// The local name of an element as written, or `nil` if the document has no such element.
  package func localName(of id: ElementID) -> String? {
    cursor(at: id)?.element.localName
  }

  /// The attributes of an element as written, or `nil` if the document has no such element.
  package func attributes(of id: ElementID) -> [String: String]? {
    cursor(at: id)?.element.attributes
  }

  /// The first element in document order whose ID is the given one, including the elements that SVGUIView doesn't
  /// render, or `nil` if there is none.
  package func element(id: String) -> ElementID? {
    guard let root else { return nil }
    func find(_ element: DocumentElement) -> ElementID? {
      // References find IDs with the whitespace around them removed, and so does this.
      if element.attributes["id"]?.trimmingCharacters(in: .whitespaces) == id { return element.id }
      for child in element.children {
        if let found = find(child) { return found }
      }
      return nil
    }
    return find(root)
  }

  /// The elements that a list of selectors matches, in document order.
  ///
  /// Selectors match against the whole document, so a selector can match an element through ancestors of the
  /// element that the search starts from.
  ///
  /// - Parameters:
  ///   - selectors: A list of selectors, separated by commas.
  ///   - scope: The element whose descendants are searched, or `nil` to search the whole document.
  /// - Throws: ``SelectorSyntaxError`` when the selectors can't be parsed.
  package func elements(matching selectors: String, in scope: ElementID? = nil) throws(SelectorSyntaxError)
    -> [ElementID]
  {
    let parser = SelectorParser(
      stylesheetOrigin: .author, namespaces: .default(), urlData: .init(URL(string: "https://example.com")!),
      forSupportsRule: false)
    guard case .success(let list) = parser.parseAuthorOriginNoNamespace(input: selectors, urlData: parser.urlData)
    else { throw SelectorSyntaxError(selectors: selectors) }
    let start: [ElementCursor]
    if let scope {
      start = cursor(at: scope)?.children ?? []
    } else {
      start = root.map { [ElementCursor(root: $0)] } ?? []
    }
    var context = MatchingContext<SVGSelectorImpl>()
    var found = [ElementID]()
    func visit(_ cursor: ElementCursor) {
      if matchesSelectorList(selectorList: list, element: cursor, context: &context) {
        found.append(cursor.element.id)
      }
      cursor.children.forEach(visit)
    }
    start.forEach(visit)
    return found
  }
}

/// The error of a list of selectors that can't be parsed.
package struct SelectorSyntaxError: Error, Equatable, Sendable {
  /// The selectors as given.
  package let selectors: String
}
