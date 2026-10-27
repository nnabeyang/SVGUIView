public protocol Element {
  associatedtype Impl: SelectorImpl

  var parent: Self? { get }
  var nextSibling: Self? { get }
  var prevSibling: Self? { get }
  var children: [Self] { get }

  func hasLocalName(_ localName: Impl.LocalName) -> Bool
  func hasId(id: Impl.Identifier, caseSensitivity: CaseSensitivity) -> Bool
  func hasClass(name: Impl.Identifier, caseSensitivity: CaseSensitivity) -> Bool
  /// Whether the element has an attribute in no namespace with the local name, whose value the operation accepts.
  func attributeMatches(localName: Impl.LocalName, operation: AttrSelectorOperation<Impl.AttrValue>) -> Bool
  /// Whether the element has no children and no text, which `:empty` matches.
  var isEmpty: Bool { get }
  /// Whether the element has the same type as another, which `:nth-of-type()` and the like count.
  func isSameType(as other: Self) -> Bool
}
