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
  let selectors: SelectorList<SelectorImpl>
  let declarations: [CSSValueType: CSSDeclaration]

  func matches(element: some SVGDrawableElement) -> Bool {
    var context = LocalMatchingContext<SelectorImpl>(shared: .init(), rightmost: .no, quirksData: nil)
    for selector in selectors.slice {
      var iter = selector.makeIterator()
      while let component = iter.next() {
        if matchesSimpleSelector(selector: component, element: element, context: &context).toBool(unknown: false) {
          return true
        }
      }
    }
    return false
  }

  subscript(key: CSSValueType) -> CSSValue? {
    declarations[key]?.value
  }
}

struct CSSStyle: Equatable {
  let rules: [CSSRule]
}
