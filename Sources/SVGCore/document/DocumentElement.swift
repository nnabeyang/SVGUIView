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
  /// The attributes, with the `href` of the XLink namespace as `href` and other prefixed attributes left out, and
  /// with the values that SMIL animations give them.
  let attributes: [String: String]
  /// The attributes without the values that SMIL animations give them, as the document has them. SMIL animations
  /// change the animated values, not the attributes, so selectors other than class selectors and the `style`
  /// attribute see these, as browsers do.
  var writtenAttributes: [String: String] { storedWrittenAttributes ?? attributes }
  /// The attributes as written for an element whose attributes SMIL animations change, which is `nil` for the others,
  /// whose attributes are as written.
  private let storedWrittenAttributes: [String: String]?
  /// The character data of `<text>`, `<tspan>` and `<style>` before each child and after the last one, one more
  /// than the children, which are empty for other elements.
  let texts: [String]
  let children: [DocumentElement]

  /// The character data of the element itself, without its children's.
  var text: String { texts.joined() }

  /// - Parameter writtenAttributes: The attributes without the values of SMIL animations, which are `attributes`
  ///   where it's `nil`.
  init(
    id: ElementID, name: SVGElementName, localName: String, attributes: [String: String],
    writtenAttributes: [String: String]? = nil, texts: [String], children: [DocumentElement]
  ) {
    precondition(texts.count == children.count + 1)
    self.id = id
    self.name = name
    self.localName = localName
    self.attributes = attributes
    storedWrittenAttributes = writtenAttributes
    self.texts = texts
    self.children = children
  }

  /// An element whose character data is all before its children.
  convenience init(
    id: ElementID, name: SVGElementName, localName: String, attributes: [String: String], text: String,
    children: [DocumentElement]
  ) {
    self.init(
      id: id, name: name, localName: localName, attributes: attributes,
      texts: [text] + Array(repeating: "", count: children.count), children: children)
  }

  /// The element with its descendant at `path`, a list of child positions from this element, replaced. The elements
  /// on the path are copied with their identifiers, and every other subtree is shared.
  func replacingDescendant(at path: ArraySlice<Int>, with replacement: DocumentElement) -> DocumentElement {
    guard let index = path.first else { return replacement }
    var children = children
    children[index] = children[index].replacingDescendant(at: path.dropFirst(), with: replacement)
    return DocumentElement(
      id: id, name: name, localName: localName, attributes: attributes, writtenAttributes: storedWrittenAttributes,
      texts: texts, children: children)
  }

  /// The element with a child inserted at a position among its children. The character data before the position
  /// stays before the new child.
  func insertingChild(_ child: DocumentElement, at index: Int) -> DocumentElement {
    var children = children
    children.insert(child, at: index)
    var texts = texts
    texts.insert("", at: index + 1)
    return DocumentElement(
      id: id, name: name, localName: localName, attributes: attributes, writtenAttributes: storedWrittenAttributes,
      texts: texts, children: children)
  }

  /// The element with character data in place of its children and its character data.
  func replacingChildren(withText text: String) -> DocumentElement {
    DocumentElement(
      id: id, name: name, localName: localName, attributes: attributes, writtenAttributes: storedWrittenAttributes,
      texts: [text], children: [])
  }

  /// The element without the child at a position. The character data before and after the child goes together.
  func removingChild(at index: Int) -> DocumentElement {
    var children = children
    children.remove(at: index)
    var texts = texts
    texts[index] += texts.remove(at: index + 1)
    return DocumentElement(
      id: id, name: name, localName: localName, attributes: attributes, writtenAttributes: storedWrittenAttributes,
      texts: texts, children: children)
  }
}

/// A parsed SVG document.
///
/// A document is a value: background work reads a document, and it stays the same however the document changes
/// later.
package struct DocumentTree: Sendable {
  /// The root element, or `nil` for data without an element.
  let root: DocumentElement?
  /// The positions of the elements, as lists of child positions from the root. Changes to attributes keep them, and
  /// insertions and removals change the ones of the elements that move.
  private let paths: [ElementID: [Int]]
  /// The languages of the user, in the order of preference, which `systemLanguage` matches.
  package let languages: [String]

  init(root: DocumentElement?, languages: [String]) {
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
    self.init(root: root, paths: paths, languages: languages)
  }

  private init(root: DocumentElement?, paths: [ElementID: [Int]], languages: [String]) {
    self.root = root
    self.paths = paths
    self.languages = languages
  }

  /// The document with the given attributes of its elements replaced by the values that SMIL animations give them,
  /// which keeps the attributes as written for the selectors.
  ///
  /// - Parameter replacements: The attributes to set by the elements that they're set on.
  func replacingAttributes(_ replacements: [ElementID: [String: String]]) -> DocumentTree {
    changingAttributes(replacements.mapValues { $0.mapValues { Optional($0) } }, isAnimated: true)
  }

  /// The document with attributes of its elements set or removed. The elements that change, and their ancestors,
  /// are copied with their identifiers, and every other subtree is shared.
  ///
  /// - Parameter changes: The values to set by the elements and the names of the attributes, with `nil` to remove an
  ///   attribute.
  /// - Parameter isAnimated: Whether the values are the ones that SMIL animations give, which change the attributes
  ///   but not the attributes as written.
  package func changingAttributes(_ changes: [ElementID: [String: String?]], isAnimated: Bool = false) -> DocumentTree {
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
          id: id, name: element.name, localName: element.localName, attributes: attributes,
          writtenAttributes: isAnimated ? element.writtenAttributes : nil, texts: element.texts,
          children: element.children))
    }
    return DocumentTree(root: root, paths: paths, languages: languages)
  }

  /// The document with the element at `path`, a list of child positions from the root, replaced.
  func replacingElement(at path: [Int], with replacement: DocumentElement) -> DocumentTree {
    DocumentTree(root: root?.replacingDescendant(at: path[...], with: replacement), languages: languages)
  }

  // MARK: - Changing the tree

  /// A document of one new element of the SVG namespace without attributes, which isn't in another document yet.
  ///
  /// - Parameters:
  ///   - localName: The name of the element, such as `rect`.
  ///   - identifier: The raw value of the identifier of the element, which no element of the document that it's
  ///     inserted in has.
  ///   - languages: The languages of the user, which the document that it's inserted in has.
  package init(elementNamed localName: String, identifier: Int, languages: [String]) {
    self.init(
      root: DocumentElement(
        id: ElementID(rawValue: identifier), name: SVGElementName(rawValue: localName) ?? .unknown, localName: localName, attributes: [:], text: "",
        children: []),
      languages: languages)
  }

  /// The document with the root of another document, and its descendants, inserted among the children of an element,
  /// or `nil` if the document doesn't have the element, the position is out of range, or the other document is empty.
  ///
  /// The parent and its ancestors are copied with their identifiers, and every other subtree is shared. The
  /// identifiers of the inserted elements must be ones that the document doesn't have.
  ///
  /// - Parameters:
  ///   - subtree: The document whose root is inserted.
  ///   - parent: The element that gets the child.
  ///   - index: The position among the children of the parent, up to their count.
  package func inserting(_ subtree: DocumentTree, into parent: ElementID, at index: Int) -> DocumentTree? {
    guard let root, let inserted = subtree.root, let parentPath = paths[parent] else { return nil }
    let parentElement = parentPath.reduce(root) { $0.children[$1] }
    guard (0...parentElement.children.count).contains(index) else { return nil }
    var paths = paths
    // The later siblings and their descendants move one position on.
    for sibling in parentElement.children[index...] {
      Self.shift(sibling, at: parentPath.count, by: 1, in: &paths)
    }
    let prefix = parentPath + [index]
    for (id, path) in subtree.paths {
      paths[id] = prefix + path
    }
    return DocumentTree(
      root: root.replacingDescendant(at: parentPath[...], with: parentElement.insertingChild(inserted, at: index)),
      paths: paths, languages: languages)
  }

  /// The document without an element and its descendants, and the document of the removed element, or `nil` if the
  /// document doesn't have the element, or the element is the root.
  package func removing(_ id: ElementID) -> (tree: DocumentTree, removed: DocumentTree)? {
    guard let root, let path = paths[id], let index = path.last else { return nil }
    let parentPath = path.dropLast()
    let parentElement = parentPath.reduce(root) { $0.children[$1] }
    let removed = DocumentTree(root: parentElement.children[index], languages: languages)
    var paths = paths
    for id in removed.paths.keys {
      paths[id] = nil
    }
    // The later siblings and their descendants move one position back.
    for sibling in parentElement.children[(index + 1)...] {
      Self.shift(sibling, at: parentPath.count, by: -1, in: &paths)
    }
    return (
      DocumentTree(
        root: root.replacingDescendant(at: parentPath, with: parentElement.removingChild(at: index)), paths: paths,
        languages: languages),
      removed
    )
  }

  /// The document with the children of an element replaced by character data, and the documents of the removed
  /// children in their order, or `nil` if the document doesn't have the element.
  ///
  /// The element and its ancestors are copied with their identifiers, and every other subtree is shared.
  package func replacingChildren(of id: ElementID, withText text: String) -> (
    tree: DocumentTree, removed: [DocumentTree]
  )? {
    guard let root, let path = paths[id] else { return nil }
    let element = path.reduce(root) { $0.children[$1] }
    let removed = element.children.map { DocumentTree(root: $0, languages: languages) }
    var paths = paths
    for tree in removed {
      for id in tree.paths.keys {
        paths[id] = nil
      }
    }
    return (
      DocumentTree(
        root: root.replacingDescendant(at: path[...], with: element.replacingChildren(withText: text)), paths: paths,
        languages: languages),
      removed
    )
  }

  /// The character data of an element and its descendants in document order, or `nil` if the document doesn't have
  /// the element. Only the elements whose character data the parser keeps, such as `<text>` and `<style>`, have
  /// it.
  package func textContent(of id: ElementID) -> String? {
    guard let element = cursor(at: id)?.element else { return nil }
    var content = ""
    func visit(_ element: DocumentElement) {
      for (index, child) in element.children.enumerated() {
        content += element.texts[index]
        visit(child)
      }
      content += element.texts[element.children.count]
    }
    visit(element)
    return content
  }

  /// Whether an element is a `<style>` element, or `false` if the document doesn't have the element.
  package func isStyleElement(_ id: ElementID) -> Bool {
    cursor(at: id)?.element.name == .style
  }

  /// Whether the document has a `<style>` element, whose style sheet a document that it's in reads.
  package var hasStyleElement: Bool {
    func visit(_ element: DocumentElement) -> Bool {
      element.name == .style || element.children.contains(where: visit)
    }
    return root.map(visit) ?? false
  }

  /// Moves the position of an element and its descendants at a depth of their paths.
  private static func shift(_ element: DocumentElement, at depth: Int, by offset: Int, in paths: inout [ElementID: [Int]]) {
    paths[element.id]?[depth] += offset
    for child in element.children {
      shift(child, at: depth, by: offset, in: &paths)
    }
  }

  // MARK: - Finding elements

  /// Whether the document has an element.
  package func contains(_ id: ElementID) -> Bool {
    paths[id] != nil
  }

  /// The largest raw value of the identifiers of the elements, or `nil` for a document without an element.
  package var largestElementID: Int? {
    paths.keys.lazy.map(\.rawValue).max()
  }

  /// The parent of an element, or `nil` if the element is the root or the document doesn't have it.
  package func parent(of id: ElementID) -> ElementID? {
    guard let root, let path = paths[id], !path.isEmpty else { return nil }
    return path.dropLast().reduce(root) { $0.children[$1] }.id
  }

  /// The children of an element, which are none if the document doesn't have the element.
  package func children(of id: ElementID) -> [ElementID] {
    guard let root, let path = paths[id] else { return [] }
    return path.reduce(root) { $0.children[$1] }.children.map(\.id)
  }

  /// Whether an element is another element or one of its descendants.
  package func isElement(_ id: ElementID, inSubtreeOf ancestor: ElementID) -> Bool {
    guard let path = paths[id], let ancestorPath = paths[ancestor] else { return false }
    return path.starts(with: ancestorPath)
  }

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
