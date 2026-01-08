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
