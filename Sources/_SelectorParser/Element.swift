public protocol Element {
  associatedtype Impl: SelectorImpl

  var parent: Self? { get }
  var nextSibling: Self? { get }
  var prevSibling: Self? { get }
  var children: [Self] { get }
  /// Whether the element is the root of its document, which `:root` matches. An element without a parent can be the
  /// root of another tree, such as the content of an SVG `<use>` element, which isn't the root.
  var isRoot: Bool { get }

  func hasLocalName(_ localName: Impl.LocalName) -> Bool
  func hasId(id: Impl.Identifier, caseSensitivity: CaseSensitivity) -> Bool
  func hasClass(name: Impl.Identifier, caseSensitivity: CaseSensitivity) -> Bool
  /// Whether the element has an attribute in no namespace with the local name, whose value the operation accepts.
  func attributeMatches(localName: Impl.LocalName, operation: AttrSelectorOperation<Impl.AttrValue>) -> Bool
  /// Whether the element has an attribute in a namespace, or in any namespace or none, with the local name, whose value
  /// the operation accepts, which an attribute selector with a namespace, such as `[xlink|href]` or `[*|href]`,
  /// matches. An empty URL is no namespace.
  func attributeMatches(
    namespace: NamespaceConstraint<Impl.NamespaceUrl>, localName: Impl.LocalName,
    operation: AttrSelectorOperation<Impl.AttrValue>
  ) -> Bool
  /// Whether the element is in the namespace of a URL, which a type selector with a namespace, such as `svg|rect`,
  /// matches.
  func hasNamespace(_ url: Impl.NamespaceUrl) -> Bool
  /// Whether the element has no children and no text, which `:empty` matches.
  var isEmpty: Bool { get }
  /// Whether the element has the same type as another, which `:nth-of-type()` and the like count.
  func isSameType(as other: Self) -> Bool
  /// Whether the element matches a pseudo-class that isn't of the structure of the tree, such as `:lang()`.
  func matchesNonTSPseudoClass(_ pseudoClass: Impl.NonTSPseudoClass) -> Bool
}

extension Element {
  /// The element without a parent is the root by default.
  public var isRoot: Bool {
    parent == nil
  }

  /// By default, the element has attributes in no namespace only, which an attribute selector with any namespace finds.
  public func attributeMatches(
    namespace: NamespaceConstraint<Impl.NamespaceUrl>, localName: Impl.LocalName,
    operation: AttrSelectorOperation<Impl.AttrValue>
  ) -> Bool {
    switch namespace {
    case .any: attributeMatches(localName: localName, operation: operation)
    case .specific: false
    }
  }

  /// By default, the element is in no namespace that a selector names.
  public func hasNamespace(_: Impl.NamespaceUrl) -> Bool {
    false
  }

  /// No pseudo-class that isn't of the structure of the tree matches by default.
  public func matchesNonTSPseudoClass(_: Impl.NonTSPseudoClass) -> Bool {
    false
  }
}
