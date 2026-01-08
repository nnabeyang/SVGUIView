public protocol SelectorVisitor {
  associatedtype Impl: SelectorImpl

  mutating func visitAttributeSelector(
    namespace: NamespaceConstraint<Impl.NamespaceUrl>,
    localName: Impl.LocalName,
    localNameLower: Impl.LocalName
  ) -> Bool

  mutating func visitSimpleSelector(_ component: Component<Impl>) -> Bool
  mutating func visitRelativeSelectorList(list: [RelativeSelector<Impl>]) -> Bool
  mutating func visitSelectorList(listKind: SelectorListKind, list: [Selector<Impl>]) -> Bool
  mutating func visitComplexSelector(combinatorToRight: Combinator?) -> Bool
}

extension SelectorVisitor {
  mutating public func visitAttributeSelector(
    namespace: NamespaceConstraint<Impl.NamespaceUrl>,
    localName: Impl.LocalName,
    localNameLower: Impl.LocalName
  ) -> Bool {
    true
  }

  mutating public func visitSimpleSelector(_: Component<Impl>) -> Bool {
    true
  }

  mutating public func visitRelativeSelectorList(list _: [RelativeSelector<Impl>]) -> Bool {
    true
  }

  mutating func visitSelectorList(listKind _: SelectorListKind, list: [Selector<Impl>]) -> Bool {
    for nested in list {
      if !nested.visit(&self) {
        return false
      }
    }
    return true
  }

  public mutating func visitComplexSelector(combinatorToRight: _SelectorParser.Combinator?) -> Bool {
    true
  }
}
