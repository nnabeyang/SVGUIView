public struct RelativeSelector<Impl: SelectorImpl>: Equatable {
  public let matchHint: RelativeSelectorMatchHint
  public let selector: Selector<Impl>

  public init(matchHint: RelativeSelectorMatchHint, selector: Selector<Impl>) {
    self.matchHint = matchHint
    self.selector = selector
  }

  static func fromSelectorList(_ selectorList: SelectorList<Impl>) -> [Self] {
    selectorList
      .slice
      .lazy
      .map { selector in
        let composition = CombinatorComposition.forRelativeSelector(selector)
        let matchHint = RelativeSelectorMatchHint(
          relativeCombinator: selector.combinatorAtParseOrder(index: 1),
          hasChildOrDescendants: composition.contains(.descendants),
          hasAdjacentOrNextSiblings: composition.contains(.siblings)
        )
        return RelativeSelector(matchHint: matchHint, selector: selector)
      }
  }
}

public struct CombinatorComposition: OptionSet, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let empty = Self([])
  public static let descendants = Self(rawValue: 1 << 0)
  public static let siblings = Self(rawValue: 1 << 1)
  public static let all: Self = [.descendants, .siblings]

  public static func forRelativeSelector<Impl: SelectorImpl>(_ innerSelector: Selector<Impl>) -> Self {
    var result = Self([])
    var iter = CombinatorIter.create(inner: innerSelector.iterSkipRelativeSelectorAnchor)
    while let combinator = iter.next() {
      switch combinator {
      case .descendant, .child:
        result.insert(.descendants)
      case .nextSibling, .laterSibling:
        result.insert(.siblings)
      case .part, .pseudoElement, .slotAssignment:
        continue
      }
      if result.contains(.all) {
        break
      }
    }
    return result
  }
}

public enum RelativeSelectorMatchHint {
  case inSubtree
  case inChild
  case inNextSibling
  case inNextSiblingSubtree
  case inSibling
  case inSiblingSubtree

  init(
    relativeCombinator: Combinator,
    hasChildOrDescendants: Bool,
    hasAdjacentOrNextSiblings: Bool
  ) {
    switch relativeCombinator {
    case .descendant:
      self = .inSubtree
    case .child:
      if !hasChildOrDescendants {
        self = .inChild
      } else {
        self = .inSubtree
      }
    case .nextSibling:
      switch (hasChildOrDescendants, hasAdjacentOrNextSiblings) {
      case (false, false):
        self = .inNextSibling
      case (false, true):
        self = .inSibling
      case (true, false):
        self = .inNextSiblingSubtree
      case (true, true):
        self = .inSiblingSubtree
      }
    case .laterSibling:
      if !hasChildOrDescendants {
        self = .inSibling
      } else {
        self = .inSiblingSubtree
      }
    case .part, .pseudoElement, .slotAssignment:
      assertionFailure("Unexpected relative combinator")
      self = .inSubtree
    }
  }

  public var isDescendantDirection: Bool {
    switch self {
    case .inChild, .inSubtree: true
    default: false
    }
  }

  public var isNextSibling: Bool {
    switch self {
    case .inNextSibling, .inNextSiblingSubtree: true
    default: false
    }
  }

  public var isSubtree: Bool {
    switch self {
    case .inSubtree, .inSiblingSubtree, .inNextSiblingSubtree: true
    default: false
    }
  }
}
