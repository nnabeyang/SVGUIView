import _SelectorParser

struct CSSRule: Equatable {
  let selectors: SelectorList<SVGSelectorImpl>
  let declarations: [CSSDeclaration]
  var sourceOrder: Int

  func matchSelector(element: some SVGDrawableElement) -> Selector<SVGSelectorImpl>? {
    var context = MatchingContext<SVGSelectorImpl>()
    for selector in selectors.slice {
      if matchesSelector(selector: selector, offset: 0, element: element, context: &context) {
        return selector
      }
    }
    return nil
  }

  subscript(key: CSSValueType) -> CSSValue? {
    nil
  }
}
