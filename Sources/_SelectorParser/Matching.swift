public struct ElementSelectorFlags: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  public static let hasSlowSelector = Self(rawValue: 1 << 0)
  public static let hasSlowSelectorLaterSiblings = Self(rawValue: 1 << 1)
  public static let hasSlowSelectorNth = Self(rawValue: 1 << 2)
  public static let hasSlowSelectorNthOf = Self(rawValue: 1 << 3)
  public static let hasEdgeChildSelector = Self(rawValue: 1 << 4)
  public static let hasEmptySelector = Self(rawValue: 1 << 5)
  public static let anchorsRelativeSelector = Self(rawValue: 1 << 6)
  public static let anchorsRelativeSelectorNonSubject = Self(rawValue: 1 << 7)
  public static let relativeSelectorSearchDirectionSibling = Self(rawValue: 1 << 8)
  public static let relativeSelectorSearchDirectionAncestor = Self(rawValue: 1 << 9)
  public static let relativeSelectorSearchDirectionAncestorSibling: Self = [
    .relativeSelectorSearchDirectionSibling,
    .relativeSelectorSearchDirectionAncestor,
  ]
}

public struct LocalMatchingContext<Impl: SelectorImpl> {
  public let shared: MatchingContext<Impl>
  public let rightmost: SubjectOrPseudoElement
  public let quirksData: SelectorIter<Impl>?

  public init(shared: MatchingContext<Impl>, rightmost: SubjectOrPseudoElement, quirksData: SelectorIter<Impl>?) {
    self.shared = shared
    self.rightmost = rightmost
    self.quirksData = quirksData
  }
}

public enum SubjectOrPseudoElement: Equatable {
  case yes
  case no
}

func matchesLocalName<E: Element>(element: E, localName: LocalName<E.Impl>) -> Bool {
  let name = selectName(element: element, localName: localName.lowerName, localNameLower: localName.lowerName)
  return element.hasLocalName(name)
}

package func compoundMatchesFeaturelessHost<Impl: SelectorImpl>(
  iter: inout SelectorIter<Impl>,
  scopeMatchesFeaturelessHost: Bool,
) -> MatchesFeaturelessHost {
  var matches: MatchesFeaturelessHost = .only
  while let component = iter.next() {
    switch component {
    case .scope where scopeMatchesFeaturelessHost,
      .implicitScope where scopeMatchesFeaturelessHost:
      break
    case .host, .pseudoElement:
      break
    case .is(let list), .where(let list):
      var anyYes = false
      var anyNo = false

      for selector in list.slice {
        switch selector.matchesFeaturelessHost(scopeMatchesFeaturelessHost: scopeMatchesFeaturelessHost) {
        case .never:
          anyNo = true
        case .yes:
          anyYes = true
          anyNo = true
        case .only:
          anyYes = true
        }
      }
      if !anyYes {
        return .never
      }
      if anyNo {
        matches = .yes
      }
    case .negation(let list):
      for selector in list.slice {
        guard case .only = selector.matchesFeaturelessHost(scopeMatchesFeaturelessHost: scopeMatchesFeaturelessHost) else {
          return .never
        }
      }
      break
    default:
      return .never
    }
  }
  return matches
}

public func matchesSelectorList<E: Element>(
  selectorList: SelectorList<E.Impl>,
  element: E,
  context: inout MatchingContext<E.Impl>,
) -> Bool {
  for selector in selectorList.slice {
    if matchesSelector(selector: selector, offset: 0, element: element, context: &context) {
      return true
    }
  }
  return false
}

enum SelectorMatchingResult: Equatable {
  case matched
  case notMatchedAndRestartFromClosestLaterSibling
  case notMatchedAndRestartFromClosestDescendant
  case notMatchedGlobally
  case unknown

  func into() -> KleeneValue {
    .init(from: self)
  }
}

extension KleeneValue {
  init(from result: SelectorMatchingResult) {
    switch result {
    case .matched: self = .true
    case .unknown: self = .unknown
    case .notMatchedAndRestartFromClosestDescendant,
      .notMatchedAndRestartFromClosestLaterSibling,
      .notMatchedGlobally:
      self = .false
    }
  }
}

public func matchesSelector<E: Element>(
  selector: Selector<E.Impl>,
  offset: Int,
  element: E,
  context: inout MatchingContext<E.Impl>
) -> Bool {
  let result = matchesSelectorKleene(selector: selector, offset: offset, element: element, context: &context)
  return result.toBool(unknown: true)
}

public func matchesSelectorKleene<E: Element>(
  selector: Selector<E.Impl>,
  offset: Int,
  element: E,
  context: inout MatchingContext<E.Impl>
) -> KleeneValue {
  matchesComplexSelector(
    iter: selector.iter(from: offset),
    element: element,
    context: &context,
    rightmost: selector.isRightmost(offset: offset) ? .yes : .no)
}

func matchesComplexSelector<E: Element>(
  iter: SelectorIter<E.Impl>,
  element: E,
  context: inout MatchingContext<E.Impl>,
  rightmost: SubjectOrPseudoElement
) -> KleeneValue {
  var iter = iter
  if context.matchingMode == .forStatelessPseudoElement && !context.isNested {
    switch iter.next() {
    case .pseudoElement(let pseudo):
      if let f = context.pseudoElementMatchingFn, !f(pseudo) {
        return .false
      }
    case .some(let other):
      assertionFailure("Used MatchingMode.forStatelessPseudoElement in a non-pseudo selector \(other)")
      return .false
    case .none:
      return .unknown
    }
    if !iter.matchesForStatelessPseudoElement() {
      return .false
    }
    assert(iter.nextSequence() == .pseudoElement)
  }
  return matchesComplexSelectorInternal(
    selectorIter: iter,
    element: element,
    context: &context,
    rightmost: rightmost,
    firstSubjectCompound: .yes
  ).into()
}

func nextElementForCombinator<E: Element>(
  element: E,
  combinator: Combinator,
  context: MatchingContext<E.Impl>
) -> (nextElement: E?, featureless: Bool) {
  switch combinator {
  case .nextSibling, .laterSibling:
    return (element.prevSibling, false)
  case .child, .descendant:
    return (element.parent, false)
  default:
    return (nil, true)
  }
}

func matchesComplexSelectorInternal<E: Element>(
  selectorIter: SelectorIter<E.Impl>,
  element: E,
  context: inout MatchingContext<E.Impl>,
  rightmost: SubjectOrPseudoElement,
  firstSubjectCompound: SubjectOrPseudoElement
) -> SelectorMatchingResult {
  var selectorIter = selectorIter
  var rightmost = rightmost
  var firstSubjectCompound = firstSubjectCompound
  let matches = matchesCompoundSelector(selectorIter: &selectorIter, element: element, context: &context, rightmost: rightmost)

  guard let combinator = selectorIter.nextSequence() else {
    switch matches {
    case .false: return .notMatchedAndRestartFromClosestLaterSibling
    case .true: return .matched
    case .unknown: return .unknown
    }
  }
  let isPseudoCombinator = combinator.isPseudoElement
  if context.featureless && !isPseudoCombinator {
    return .notMatchedGlobally
  }

  let isSiblingCombinator = combinator.isSibling

  if matches == .false {
    return .notMatchedAndRestartFromClosestLaterSibling
  }
  if !isPseudoCombinator {
    rightmost = .no
    firstSubjectCompound = .no
  }
  let candidateNotFound: SelectorMatchingResult = isSiblingCombinator ? .notMatchedAndRestartFromClosestDescendant : .notMatchedGlobally

  var element = element
  while true {
    let (nextElement, featureless) = nextElementForCombinator(element: element, combinator: combinator, context: context)
    guard let nextElement else {
      return candidateNotFound
    }
    element = nextElement
    let result = context.withFeatureless(featureless: featureless) { context in
      matchesComplexSelectorInternal(
        selectorIter: selectorIter,
        element: element,
        context: &context,
        rightmost: rightmost,
        firstSubjectCompound: firstSubjectCompound
      )
    }
    switch result {
    case .matched:
      assert(matches.toBool(unknown: true), "Compound didn't match?")
      if !matches.toBool(unknown: false) {
        return .unknown
      }
      return result
    case .unknown, .notMatchedGlobally:
      return result
    default:
      break
    }
    switch combinator {
    case .descendant:
      break
    case .child:
      return .notMatchedAndRestartFromClosestDescendant
    case .laterSibling:
      if case .notMatchedAndRestartFromClosestDescendant = result {
        return result
      }
    case .nextSibling, .pseudoElement, .part, .slotAssignment:
      return result
    }
    if featureless {
      return candidateNotFound
    }
  }
}

public func matchesCompoundSelector<E: Element>(
  selectorIter: inout SelectorIter<E.Impl>,
  element: E,
  context: inout MatchingContext<E.Impl>,
  rightmost: SubjectOrPseudoElement
) -> KleeneValue {
  if context.featureless
    && compoundMatchesFeaturelessHost(iter: &selectorIter, scopeMatchesFeaturelessHost: true) == .never
  {
    return .false
  }
  var quirksData: SelectorIter<E.Impl>?
  if case .quirks = context.quirksMode {
    quirksData = selectorIter
  }
  var localContext = LocalMatchingContext(
    shared: context,
    rightmost: rightmost,
    quirksData: quirksData
  )
  return KleeneValue.anyFalse(iter: &selectorIter) { simple in
    matchesSimpleSelector(selector: simple, element: element, context: &localContext)
  }
}

public func matchesSimpleSelector<E: Element>(
  selector: Component<E.Impl>,
  element: E,
  context: inout LocalMatchingContext<E.Impl>
) -> KleeneValue {
  assert(context.shared.isNested || !context.shared.inNegation)
  let value: Bool
  switch selector {
  case .id(let id):
    value = element.hasId(id: id, caseSensitivity: context.shared.classesAndIdsCaseSensitivity)
  case .class(let name):
    value = element.hasClass(name: name, caseSensitivity: context.shared.classesAndIdsCaseSensitivity)
  case .localName(let localName):
    value = matchesLocalName(element: element, localName: localName)
  case .explicitUniversalType, .explicitAnyNamespace:
    value = true
  case .combinator:
    fatalError("Shouldn't try to selector-match combinators")
  case .invalid:
    value = false
  default:
    return .unknown
  }
  return .from(value)
}

public func selectName<E: Element>(
  element: E,
  localName: E.Impl.LocalName,
  localNameLower: E.Impl.LocalName
) -> E.Impl.LocalName {
  if localName == localNameLower {
    localNameLower
  } else {
    localName
  }
}
