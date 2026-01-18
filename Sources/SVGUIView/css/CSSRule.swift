import _SelectorParser

enum CSSRule: Equatable {
  case qualified(QualifiedCSSRule)

  func matches(element: any SVGDrawableElement) -> Bool {
    switch self {
    case .qualified(let rule):
      return rule.matches(element: element)
    }
  }

  var declarations: [CSSValueType: CSSDeclaration] {
    switch self {
    case .qualified(let rule):
      return rule.declarations
    }
  }
}

enum CSSRuleType: String {
  case qualified
}

struct QualifiedCSSRule: Equatable {
  let selectors: SelectorList<SVGSelectorImpl>
  let declarations: [CSSValueType: CSSDeclaration]

  func matches(element: some SVGDrawableElement) -> Bool {
    var context = MatchingContext<SVGSelectorImpl>()
    for selector in selectors.slice {
      if matchesSelector(selector: selector, offset: 0, element: element, context: &context) {
        return true
      }
    }
    return false
  }

  subscript(key: CSSValueType) -> CSSValue? {
    declarations[key]?.value
  }
}
