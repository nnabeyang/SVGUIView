import _SelectorParser

struct Namespaces {
  let `default`: Namespace?
  let prefixes: [Prefix: Namespace]
}

extension Namespaces: Default {
  static func `default`() -> Namespaces {
    .init(default: nil, prefixes: [:])
  }
}

struct Stylesheet: Sendable {
  let rules: [CSSRule]
  /// The `@keyframes` rules by their names. Of the rules with the same name, the last one wins.
  let keyframes: [String: KeyframesRule]
  /// Whether a selector has a sibling combinator, `+` or `~`, so that an element's attributes can change what the
  /// rules give its later siblings and their descendants.
  let hasSiblingCombinators: Bool
  /// The names of the attributes that the attribute selectors match, so that changing another attribute that isn't a
  /// property doesn't change which rules match.
  let selectorAttributes: Set<String>

  init(rules: [CSSRule], keyframes: [String: KeyframesRule] = [:]) {
    self.rules = rules
    self.keyframes = keyframes
    var finder = SiblingCombinatorFinder()
    hasSiblingCombinators = rules.contains { rule in rule.selectors.slice.contains { !$0.visit(&finder) } }
    var attributeFinder = SelectorAttributeFinder()
    for rule in rules {
      for selector in rule.selectors.slice {
        _ = selector.visit(&attributeFinder)
      }
    }
    selectorAttributes = attributeFinder.names
  }

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

/// Stops at the first sibling combinator of a selector, including the ones in the selectors of `:not()` and `:is()`.
private struct SiblingCombinatorFinder: SelectorVisitor {
  typealias Impl = SVGSelectorImpl

  mutating func visitSelectorList(listKind _: SelectorListKind, list: [Selector<Impl>]) -> Bool {
    list.allSatisfy { $0.visit(&self) }
  }

  mutating func visitComplexSelector(combinatorToRight: Combinator?) -> Bool {
    !(combinatorToRight?.isSibling ?? false)
  }
}

/// Collects the names of the attributes that the attribute selectors of selectors match, also in the selectors of
/// pseudo-classes such as `:not()`.
private struct SelectorAttributeFinder: SelectorVisitor {
  typealias Impl = SVGSelectorImpl

  var names = Set<String>()

  mutating func visitAttributeSelector(
    namespace _: NamespaceConstraint<Impl.NamespaceUrl>, localName: Impl.LocalName, localNameLower: Impl.LocalName
  ) -> Bool {
    names.insert(localName.rawValue)
    names.insert(localNameLower.rawValue)
    return true
  }

  mutating func visitSelectorList(listKind _: SelectorListKind, list: [Selector<Impl>]) -> Bool {
    for selector in list {
      _ = selector.visit(&self)
    }
    return true
  }
}
