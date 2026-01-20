public protocol Element {
  associatedtype Impl: SelectorImpl

  var parent: Self? { get }
  var nextSibling: Self? { get }
  var prevSibling: Self? { get }
  var children: [Self] { get }

  func hasLocalName(_ localName: Impl.LocalName) -> Bool
  func hasId(id: Impl.Identifier, caseSensitivity: CaseSensitivity) -> Bool
  func hasClass(name: Impl.Identifier, caseSensitivity: CaseSensitivity) -> Bool
}
