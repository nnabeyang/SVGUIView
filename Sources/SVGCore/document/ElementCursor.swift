import Foundation
import _SelectorParser

/// An element of a document with the path to it from the root, which selector matching walks up and back along.
///
/// Elements don't know their parents, so selector matching, which looks at ancestors and previous siblings, matches
/// a cursor instead of an element.
struct ElementCursor {
  /// An ancestor of the element, and the position among its children of the next element on the path.
  private struct Step {
    let element: DocumentElement
    let childIndex: Int
  }

  let element: DocumentElement
  /// The ancestors of the element, from the root.
  private let ancestors: [Step]

  /// A cursor at the root of a document.
  init(root: DocumentElement) {
    self.init(element: root, ancestors: [])
  }

  private init(element: DocumentElement, ancestors: [Step]) {
    self.element = element
    self.ancestors = ancestors
  }

  /// The cursor at the child of the element at the given position.
  func child(at index: Int) -> ElementCursor {
    ElementCursor(element: element.children[index], ancestors: ancestors + [Step(element: element, childIndex: index)])
  }

  /// The cursor at the sibling `offset` positions after the element, or `nil` if there is none.
  private func sibling(offset: Int) -> ElementCursor? {
    guard let parent = ancestors.last else { return nil }
    let index = parent.childIndex + offset
    guard parent.element.children.indices.contains(index) else { return nil }
    return ElementCursor(
      element: parent.element.children[index],
      ancestors: ancestors.dropLast() + [Step(element: parent.element, childIndex: index)])
  }
}

extension ElementCursor: Element {
  typealias Impl = SVGSelectorImpl

  var parent: ElementCursor? {
    guard let parent = ancestors.last else { return nil }
    return ElementCursor(element: parent.element, ancestors: Array(ancestors.dropLast()))
  }

  /// Whether the element is a span of text: a `<tspan>` or an `<a>` whose ancestors up to a `<text>` are spans.
  var isInText: Bool {
    var cursor = self
    while cursor.element.name == .tspan || cursor.element.name == .a, let parent = cursor.parent {
      if parent.element.name == .text { return true }
      cursor = parent
    }
    return false
  }

  var prevSibling: ElementCursor? {
    sibling(offset: -1)
  }

  var nextSibling: ElementCursor? {
    sibling(offset: 1)
  }

  var children: [ElementCursor] {
    element.children.indices.map(child(at:))
  }

  func hasLocalName(_ localName: Impl.LocalName) -> Bool {
    Impl.LocalName.from(element.localName) == localName
  }

  func hasId(id: GenericAtomIdent<IdentStaticSet>, caseSensitivity _: _SelectorParser.CaseSensitivity) -> Bool {
    element.attributes["id"]?.trimmingCharacters(in: .whitespaces) == id.rawValue
  }

  func hasClass(name: GenericAtomIdent<IdentStaticSet>, caseSensitivity _: _SelectorParser.CaseSensitivity) -> Bool {
    // The class attribute is a list of names separated by ASCII whitespace.
    guard let classes = element.attributes["class"] else { return false }
    return classes.split(whereSeparator: { " \t\n\r\u{0C}".contains($0) }).contains { $0 == name.rawValue }
  }

  func attributeMatches(localName: Impl.LocalName, operation: AttrSelectorOperation<Impl.AttrValue>) -> Bool {
    guard let attribute = element.attributes[localName.rawValue] else { return false }
    switch operation {
    case .exists:
      return true
    case .withValue(let op, let caseSensitivity, let value):
      return op.evalString(elementAttrValue: attribute, attrSelectorValue: value.rawValue, caseSensitivity: caseSensitivity)
    }
  }

  var isEmpty: Bool {
    element.children.isEmpty && element.text.isEmpty
  }

  func isSameType(as other: ElementCursor) -> Bool {
    element.localName == other.element.localName
  }
}
