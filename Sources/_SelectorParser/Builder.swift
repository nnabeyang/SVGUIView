import Foundation

public struct SelectorBuilder<Impl: SelectorImpl> {
  public var components: [Component<Impl>]
  public var lastCompoundStart: Int?

  public init(components: [Component<Impl>], lastCompoundStart: Int?) {
    self.components = components
    self.lastCompoundStart = lastCompoundStart
  }

  public mutating func pushSimpleSelector(_ ss: Component<Impl>) {
    assert(!ss.isCombinator)
    components.append(ss)
  }

  public mutating func pushCombinator(_ c: Combinator) {
    reverseLastCompound()
    components.append(.combinator(c))
    lastCompoundStart = components.count
  }

  mutating func reverseLastCompound() {
    let start = lastCompoundStart ?? 0
    components[start...].reverse()
  }

  public var hasCombinators: Bool {
    lastCompoundStart != nil
  }

  public mutating func build(parseRelative: ParseRelative) -> SelectorData<Impl> {
    let sf = specificityAndFlags(iter: components.makeIterator(), forNestingParent: false)
    return buildWithSpecificityAndFlags(spec: sf, parseRelative: parseRelative)
  }

  public mutating func buildWithSpecificityAndFlags(
    spec: SpecificityAndFlags,
    parseRelative: ParseRelative
  ) -> SelectorData<Impl> {
    var spec = spec
    let implicitAddition: (Component<Impl>, SelectorFlags)? =
      switch parseRelative {
      case .forNesting where !spec.flags.contains(.hasParent):
        (.parentSelector, .hasParent)
      case .forScope where !spec.flags.contains(.hasScope) && !spec.flags.contains(.hasParent):
        (.implicitScope, .hasScope)
      default:
        nil
      }

    let implicitSelector: [Component<Impl>]
    if let (comp, flag) = implicitAddition {
      spec.flags.insert(flag)
      implicitSelector = [.combinator(.descendant), comp]
    } else {
      implicitSelector = []
    }

    if lastCompoundStart == nil {
      return .init(slice: components + implicitSelector, header: spec)
    }
    reverseLastCompound()
    return .init(slice: components.reversed() + implicitSelector, header: spec)
  }
}

extension SelectorBuilder: Default {
  public static func `default`() -> Self {
    SelectorBuilder(
      components: [],
      lastCompoundStart: nil
    )
  }
}

extension SelectorBuilder: Push {
  public typealias Element = Component<Impl>
  public mutating func push(_ value: Component<Impl>) {
    pushSimpleSelector(value)
  }
}

func specificityAndFlags<Impl: SelectorImpl>(
  iter: [Component<Impl>].Iterator,
  forNestingParent: Bool
) -> SpecificityAndFlags {
  func componentSpecificity(
    simpleSelector: Component<Impl>,
    specificity: inout Specificity,
    flags: inout SelectorFlags,
    forNestingParent: Bool
  ) {
    switch simpleSelector {
    case .combinator:
      break
    case .parentSelector:
      flags.insert(.hasParent)
    case .part:
      flags.insert(.hasPart)
      if !forNestingParent {
        specificity.elementSelectors += 1
      }
    case .pseudoElement(let pseudo):
      flags.insert(.hasPseudo)
      if !forNestingParent {
        specificity.elementSelectors += pseudo.specificityCount()
      }
    case .localName:
      specificity.elementSelectors += 1
    case .slotted(let selector):
      flags.insert(.hasSlotted)
      if !forNestingParent {
        specificity.elementSelectors += 1
        // See: https://github.com/w3c/csswg-drafts/issues/1915
        specificity += Specificity.from(selector.specificity)
      }
    case .host(let selector):
      flags.insert(.hasHost)
      specificity.classLikeSelectors += 1
      if let selector {
        // See: https://github.com/w3c/csswg-drafts/issues/1915
        specificity += Specificity.from(selector.specificity)
        flags.insert(selector.flags)
      }
    case .id:
      specificity.idSelectors += 1
    case .class,
      .attributeInNoNamespace,
      .attributeInNoNamespaceExists,
      .attributeOther,
      .root,
      .empty,
      .nth,
      .nonTSPseudoClass:
      specificity.classLikeSelectors += 1
    case .scope, .implicitScope:
      flags.insert(.hasScope)
      if case .scope = simpleSelector {
        specificity.classLikeSelectors += 1
      }
    case .nthOf(let nthOfData):
      // https://drafts.csswg.org/selectors/#specificity-rules:
      specificity.classLikeSelectors += 1
      var iter = nthOfData.selectors.makeIterator()
      let sf = selectorListSpecificityAndFlags(
        iter: &iter,
        forNestingParent: forNestingParent
      )
      specificity += Specificity.from(sf.specificity)
      flags.insert(sf.flags)
    // https://drafts.csswg.org/selectors/#specificity-rules:
    case .where(let list), .negation(let list), .is(let list):
      var iter = list.slice.makeIterator()
      let sf = selectorListSpecificityAndFlags(
        iter: &iter,
        forNestingParent: true
      )
      switch simpleSelector {
      case .where:
        break
      default:
        specificity += Specificity.from(sf.specificity)

      }
      flags.insert(sf.flags)
    case .has(let relativeSelectors):
      var iter = relativeSelectors.makeIterator()
      let sf = relativeSelectorListSpecificityAndFlags(iter: &iter, forNestingParent: forNestingParent)
      specificity += Specificity.from(sf.specificity)
      flags.insert(sf.flags)
    case .explicitUniversalType,
      .explicitAnyNamespace,
      .explicitNoNamespace,
      .defaultNamespace,
      .namespace,
      .relativeSelectorAnchor,
      .invalid:
      break
    }
  }

  var specificity = Specificity.default()
  var flags = SelectorFlags.default()
  for simpleSelector in iter {
    componentSpecificity(
      simpleSelector: simpleSelector,
      specificity: &specificity,
      flags: &flags,
      forNestingParent: forNestingParent
    )
  }
  return SpecificityAndFlags(specificity: specificity.into(), flags: flags)
}

public func selectorListSpecificityAndFlags<Impl: SelectorImpl, Iter: IteratorProtocol>(
  iter: inout Iter,
  forNestingParent: Bool
) -> SpecificityAndFlags where Iter.Element == Selector<Impl> {
  var specificity: UInt32 = 0
  var flags = SelectorFlags.empty
  while let selector = iter.next() {
    let selectorFlags = selector.flags
    let selectorSpecificity =
      if forNestingParent && selectorFlags.contains(.empty) {
        specificityAndFlags(iter: selector.iterRawMatchOrder(), forNestingParent: forNestingParent).specificity
      } else {
        selector.specificity
      }
    specificity = max(specificity, selectorSpecificity)
    flags.insert(selector.flags)
  }
  return SpecificityAndFlags(specificity: specificity, flags: flags)
}

public func relativeSelectorListSpecificityAndFlags<Impl: SelectorImpl>(
  iter: inout [RelativeSelector<Impl>].Iterator,
  forNestingParent: Bool
) -> SpecificityAndFlags {
  var iter = iter.lazy.map(\.selector).makeIterator()
  return selectorListSpecificityAndFlags(iter: &iter, forNestingParent: forNestingParent)
}
