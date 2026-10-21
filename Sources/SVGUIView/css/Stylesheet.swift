import _SelectorParser

public struct Namespaces {
  public let `default`: Namespace?
  public let prefixes: [Prefix: Namespace]
}

extension Namespaces: Default {
  public static func `default`() -> Namespaces {
    .init(default: nil, prefixes: [:])
  }
}

struct Stylesheet {
  let rules: [CSSRule]

  func matchElement(element: ElementCursor) -> [RuleMatch] {
    var matches = [RuleMatch]()
    for rule in self.rules {
      guard let selector = rule.matchSelector(element: element) else { continue }
      let specificity = selector.specificity
      var declarations = [CSSDeclaration]()
      for declaration in rule.declarations {
        declarations.append(
          CSSDeclaration(
            declaration: declaration.declaration,
            importance: declaration.importance,
            specificity: .from(specificity),
            sourceOrder: rule.sourceOrder * 10000 + declaration.sourceOrder
          ))
      }
      matches.append(
        RuleMatch(
          specificity: .from(specificity),
          declarations: declarations,
          sourceOrder: rule.sourceOrder))
    }
    return matches
  }
}
