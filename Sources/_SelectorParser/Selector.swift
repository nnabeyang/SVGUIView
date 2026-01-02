import Foundation
import _CSSParser

public struct Specificity: Into, Default {
  public var idSelectors: UInt32
  public var classLikeSelectors: UInt32
  public var elementSelectors: UInt32

  public static func singleClassLike() -> Self {
    Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0)
  }

  public static func `default`() -> Self {
    Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0)
  }
}

func + (lhs: Specificity, rhs: Specificity) -> Specificity {
  return Specificity(
    idSelectors: lhs.idSelectors + rhs.idSelectors,
    classLikeSelectors: lhs.classLikeSelectors + rhs.classLikeSelectors,
    elementSelectors: lhs.elementSelectors + rhs.elementSelectors
  )
}

func += (lhs: inout Specificity, rhs: Specificity) {
  lhs = lhs + rhs
}

let MAX_10BIT: UInt32 = 1 << 10 - 1

extension Specificity: From {
  public typealias From = UInt32
  public static func from(_ value: From) -> Self {
    assert(value <= MAX_10BIT << 20 | MAX_10BIT << 10 | MAX_10BIT)
    return Self(idSelectors: value >> 20, classLikeSelectors: (value >> 10) & MAX_10BIT, elementSelectors: value & MAX_10BIT)
  }
}

extension UInt32: From {
  public typealias From = Specificity
  public static func from(_ specificity: From) -> Self {
    Swift.min(specificity.idSelectors, MAX_10BIT) << 20 | Swift.min(specificity.classLikeSelectors, MAX_10BIT) << 10 | Swift.min(specificity.elementSelectors, MAX_10BIT)
  }
}

public struct SelectorFlags: OptionSet, Sendable, Default {
  public let rawValue: UInt8
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let empty = Self([])
  public static let hasPseudo = Self(rawValue: 1 << 0)
  public static let hasSlotted = Self(rawValue: 1 << 1)
  public static let hasPart = Self(rawValue: 1 << 2)
  public static let hasParent = Self(rawValue: 1 << 3)
  public static let hasHost = Self(rawValue: 1 << 4)
  public static let hasScope = Self(rawValue: 1 << 5)
  public static let forbiddenForNesting: Self = [.hasPseudo, .hasSlotted, .hasPart]
  public static func `default`() -> SelectorFlags { .empty }
}

public struct SpecificityAndFlags: Equatable {
  public let specificity: UInt32
  public var flags: SelectorFlags
}

public struct SelectorData<Impl: SelectorImpl>: Equatable {
  let slice: [Component<Impl>]
  let header: SpecificityAndFlags

  public init(slice: [Component<Impl>], header: SpecificityAndFlags) {
    self.slice = slice
    self.header = header
  }

  public init(slice: [Component<Impl>], specificity: Specificity, flags: SelectorFlags) {
    self.slice = slice
    self.header = SpecificityAndFlags(specificity: specificity.into(), flags: flags)
  }

  public var count: Int { slice.count }
}

public struct Selector<Impl: SelectorImpl>: Equatable {
  let data: SelectorData<Impl>

  public init(_ data: SelectorData<Impl>) {
    self.data = data
  }

  public init(slice: [Component<Impl>], specificity: Specificity, flags: SelectorFlags) {
    var builder = SelectorBuilder<Impl>.default()
    for component in slice {
      if let combinator = component.asCombinator() {
        builder.pushCombinator(combinator)
      } else {
        builder.pushSimpleSelector(component)
      }
    }
    let spec = SpecificityAndFlags(specificity: specificity.into(), flags: flags)
    self.init(builder.buildWithSpecificityAndFlags(spec: spec, parseRelative: .no))
  }

  static func scope() -> Self {
    Self(SelectorData(slice: [.scope], header: .init(specificity: Specificity.singleClassLike().into(), flags: .hasScope)))
  }

  static func implicitScope() -> Self {
    Self(SelectorData(slice: [.scope], header: .init(specificity: Specificity.singleClassLike().into(), flags: .hasScope)))
  }

  public var specificity: UInt32 {
    data.header.specificity
  }

  public var flags: SelectorFlags {
    data.header.flags
  }

  public var hasPseudoElement: Bool {
    flags.contains(.hasPseudo)
  }

  public var hasParentSelector: Bool {
    flags.contains(.hasParent)
  }

  public var isSlotted: Bool {
    data.header.flags.contains(.hasSlotted)
  }

  public var isPart: Bool {
    data.header.flags.contains(.hasPart)
  }

  public var parts: [Impl.Identifier]? {
    guard isPart else { return nil }
    var iter = makeIterator()
    if hasPseudoElement {
      while iter.next() != nil {}
      let combinator = iter.nextSequence()
      assert(combinator == .pseudoElement)
    }

    while let component = iter.next() {
      if case .part(let part) = component {
        return part
      }
    }
    assertionFailure("is_part() lied somehow?")
    return nil
  }

  public func pseudoElement() -> Impl.PseudoElement? {
    guard hasPseudoElement else { return nil }
    var iter = makeIterator()
    while let component = iter.next() {
      if case .pseudoElement(let pseudo) = component {
        return pseudo
      }
    }
    assertionFailure("has_pseudo_element lied!")
    return nil
  }

  public func pseudoElements() -> [Impl.PseudoElement] {
    guard hasPseudoElement else { return [] }
    var iter = makeIterator()
    var pseudos = [Impl.PseudoElement]()
    loop: while true {
      while let component = iter.next() {
        if case .pseudoElement(let pseudo) = component {
          pseudos.append(pseudo)
        }
      }
      switch iter.nextSequence() {
      case .pseudoElement: continue
      default: break loop
      }
    }

    assert(!pseudos.isEmpty, "has_pseudo_element lied!")
    return pseudos
  }

  public var isUniversal: Bool {
    iterRawMatchOrder().allSatisfy {
      switch $0 {
      case .explicitUniversalType, .explicitAnyNamespace, .combinator(.pseudoElement), .pseudoElement: true
      default: false
      }
    }
  }

  public func matchesFeaturelessHost(scopeMatchesFeaturelessHost: Bool) -> MatchesFeaturelessHost {
    let flags = flags
    if !flags.contains(.hasHost) || flags.contains(.hasScope) {
      return .never
    }

    var iter = makeIterator()
    if flags.contains(.hasPseudo) {
      while iter.next() != nil {
        // Skip over pseudo-elements
      }
      switch iter.nextSequence() {
      case .some(let c) where c.isPseudoElement:
        break
      default:
        assertionFailure("Pseudo selector without pseudo combinator?")
        return .never
      }
    }

    let compoundMatches = compoundMatchesFeaturelessHost(iter: &iter, scopeMatchesFeaturelessHost: scopeMatchesFeaturelessHost)
    guard iter.nextSequence() == nil else {
      return .never
    }
    return compoundMatches
  }

  public func makeIterator() -> SelectorIter<Impl> {
    SelectorIter(components: self.data.slice, nextCombinator: nil)
  }

  public var iterSkipRelativeSelectorAnchor: SelectorIter<Impl> {
    SelectorIter(components: data.slice[..<(data.slice.count - 2)])
  }

  public func iter(from offset: Int) -> SelectorIter<Impl> {
    SelectorIter(components: data.slice[offset...])
  }

  public func combinatorAtMatchOrder(index: Int) -> Combinator? {
    switch data.slice[index] {
    case .combinator(let c): c
    case let other:
      fatalError("Expected a combinator at match-order (left-to-right) index \(index), found \(other)")
    }
  }

  func iterRawMatchOrder() -> [Component<Impl>].Iterator {
    self.data.slice.makeIterator()
  }

  public func combinatorAtParseOrder(index: Int) -> Combinator {
    switch data.slice[count - index - 1] {
    case .combinator(let c):
      c
    case let other:
      fatalError("Expected a combinator at parse-order (right-to-left) index \(index), found \(other)")
    }
  }

  public func iterRawParseOrder(from offset: Int) -> ReversedCollection<ArraySlice<Component<Impl>>>.Iterator {
    data.slice[...(count - offset)].reversed().makeIterator()
  }

  public func replaceParentSelector(parent: SelectorList<Impl>) -> Self {
    var iter = parent.slice.makeIterator()
    let parentSpecificityAndFlags = selectorListSpecificityAndFlags(iter: &iter, forNestingParent: true)

    var specificity: Specificity = .from(specificity)
    var flags = flags.subtracting(.hasParent)
    let forbiddenFlags: SelectorFlags = .forbiddenForNesting

    func replaceParentOnSelectorList(
      orig: [Selector<Impl>],
      parent: SelectorList<Impl>,
      specificity: inout Specificity,
      flags: inout SelectorFlags,
      propagateSpecificity: Bool,
      forbiddenFlags: SelectorFlags
    ) -> SelectorList<Impl>? {
      if !orig.contains(where: \.hasParentSelector) {
        return nil
      }
      let result = SelectorList(slice: orig.map({ $0.replaceParentSelector(parent: parent) }))
      var iter = result.slice.makeIterator()
      let resultSpecificityAndFlags = selectorListSpecificityAndFlags(iter: &iter, forNestingParent: false)
      if propagateSpecificity {
        var iter = orig.makeIterator()
        specificity += .from(
          resultSpecificityAndFlags.specificity
            - selectorListSpecificityAndFlags(iter: &iter, forNestingParent: false).specificity)
      }
      flags.insert(resultSpecificityAndFlags.flags.subtracting(forbiddenFlags))
      return result
    }

    func replaceParentOnRelativeSelectorList(
      orig: [RelativeSelector<Impl>],
      parent: SelectorList<Impl>,
      specificity: inout Specificity,
      flags: inout SelectorFlags,
      forbiddenFlags: SelectorFlags,
    ) -> [RelativeSelector<Impl>] {
      var any = false
      let result = orig.map { s in
        if !s.selector.hasParentSelector {
          return s
        }
        any = true
        return RelativeSelector(
          matchHint: s.matchHint,
          selector: s.selector.replaceParentSelector(parent: parent)
        )
      }
      guard any else {
        return result
      }
      var iter = result.makeIterator()
      let resultSpecificityAndFlags = relativeSelectorListSpecificityAndFlags(iter: &iter, forNestingParent: false)
      iter = orig.makeIterator()
      flags.insert(resultSpecificityAndFlags.flags.subtracting(forbiddenFlags))
      specificity += .from(
        resultSpecificityAndFlags.specificity
          - relativeSelectorListSpecificityAndFlags(iter: &iter, forNestingParent: false).specificity
      )
      return result
    }

    func replaceParentOnSelector(
      orig: Selector<Impl>,
      parent: SelectorList<Impl>,
      specificity: inout Specificity,
      flags: inout SelectorFlags,
      forbiddenFlags: SelectorFlags
    ) -> Selector<Impl> {
      let newSelector = orig.replaceParentSelector(parent: parent)
      specificity += .from(newSelector.specificity - orig.specificity)
      flags.insert(newSelector.flags.subtracting(forbiddenFlags))
      return newSelector
    }
    guard hasParentSelector else {
      return self
    }
    let items: [Component<Impl>] = iterRawMatchOrder().map { component in
      switch component {
      case .localName,
        .id,
        .class,
        .attributeInNoNamespaceExists,
        .attributeInNoNamespace,
        .attributeOther,
        .explicitUniversalType,
        .explicitAnyNamespace,
        .explicitNoNamespace,
        .defaultNamespace,
        .namespace,
        .root,
        .empty,
        .scope,
        .implicitScope,
        .nth,
        .nonTSPseudoClass,
        .pseudoElement,
        .combinator,
        .host(.none),
        .part,
        .invalid,
        .relativeSelectorAnchor:
        return component
      case .parentSelector:
        specificity += .from(parentSpecificityAndFlags.specificity)
        flags.insert(parentSpecificityAndFlags.flags.subtracting(forbiddenFlags))
        return .is(parent)
      case .negation(let selectors):
        let newSelectors =
          replaceParentOnSelectorList(
            orig: selectors.slice,
            parent: parent,
            specificity: &specificity,
            flags: &flags,
            propagateSpecificity: true,
            forbiddenFlags: forbiddenFlags) ?? selectors
        return .negation(newSelectors)
      case .is(let selectors):
        let newSelectors =
          replaceParentOnSelectorList(
            orig: selectors.slice,
            parent: parent,
            specificity: &specificity,
            flags: &flags,
            propagateSpecificity: true,
            forbiddenFlags: forbiddenFlags) ?? selectors
        return .is(newSelectors)
      case .where(let selectors):
        let newSelectors =
          replaceParentOnSelectorList(
            orig: selectors.slice,
            parent: parent,
            specificity: &specificity,
            flags: &flags,
            propagateSpecificity: false,
            forbiddenFlags: forbiddenFlags) ?? selectors
        return .where(newSelectors)
      case .has(let selectors):
        return .has(
          replaceParentOnRelativeSelectorList(
            orig: selectors,
            parent: parent,
            specificity: &specificity,
            flags: &flags,
            forbiddenFlags: forbiddenFlags))
      case .host(.some(let selector)):
        return .host(
          replaceParentOnSelector(
            orig: selector,
            parent: parent,
            specificity: &specificity,
            flags: &flags,
            forbiddenFlags: forbiddenFlags))
      case .nthOf(let data):
        if let selectors = replaceParentOnSelectorList(
          orig: data.selectors,
          parent: parent,
          specificity: &specificity,
          flags: &flags,
          propagateSpecificity: true,
          forbiddenFlags: forbiddenFlags)
        {
          return .nthOf(.init(nthData: data.nthData, selectors: selectors.slice))
        } else {
          return .nthOf(data)
        }
      case .slotted(let selector):
        let newSelector = replaceParentOnSelector(
          orig: selector,
          parent: parent,
          specificity: &specificity,
          flags: &flags,
          forbiddenFlags: forbiddenFlags)
        return .slotted(newSelector)
      }
    }
    return Selector(.init(slice: items, header: .init(specificity: specificity.into(), flags: flags)))
  }

  public var count: Int {
    data.count
  }

  public func visit<V: SelectorVisitor>(_ visitor: inout V) -> Bool where V.Impl == Impl {
    var current = makeIterator()
    var combinator: Combinator? = nil
    while true {
      guard visitor.visitComplexSelector(combinatorToRight: combinator) else {
        return false
      }
      while let selector = current.next() {
        if !selector.visit(visitor: &visitor) {
          return false
        }
      }
      combinator = current.nextSequence()
      if combinator == nil {
        break
      }
    }
    return true
  }

  public static func createInvalid(input: String) -> Self {
    func checkForParent(input: inout CSSParser, hasParent: inout Bool) {
      while case .success(let token) = input.next() {
        switch token {
        case .function, .parenthesisBlock, .curlyBracketBlock, .squareBracketBlock:
          let _: Result<(), ParseError<DummyError>> = input.parseNestedBlock {
            checkForParent(input: &$0, hasParent: &hasParent)
            return .success(())
          }
        case .delim("&"):
          hasParent = true
        default:
          break
        }
        if hasParent {
          break
        }
      }
    }
    var hasParent = false
    let parserInput = ParserInput(input: input)
    var parser = CSSParser(input: parserInput)
    checkForParent(input: &parser, hasParent: &hasParent)
    return Self.init(
      .init(
        slice: [.invalid(input.trimmingCharacters(in: .whitespacesAndNewlines))],
        header: SpecificityAndFlags(specificity: 0, flags: hasParent ? .hasParent : .empty)))
  }

  public func isRightmost(offset: Int) -> Bool {
    offset == 0 || combinatorAtMatchOrder(index: offset - 1) == .pseudoElement
  }
}

extension Selector: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    var combinators = data.slice.lazy.reversed().compactMap({ $0.asCombinator() }).makeIterator()
    let compoundSelectors = data.slice.lazy.lazySplit(whereSeparator: { $0.isCombinator }).reversed()
    var combinatorsExhausted = false
    loop: for compound in compoundSelectors {
      assert(!combinatorsExhausted)

      // https://drafts.csswg.org/cssom/#serializing-selectors
      let firstCompound: Component<Impl>
      switch compound.first {
      case .none:
        continue loop
      case .some(let c):
        firstCompound = c
      }

      switch firstCompound {
      case .relativeSelectorAnchor, .implicitScope:
        assert(compound.count == 1, ".relativeSelectorAnchor/.implicitScope should only be a simple selector")
        if let c = combinators.next() {
          c.toCSSRelative(to: &dest)
        } else {
          guard case .implicitScope = firstCompound else {
            assertionFailure("Only implicit :scope may not have any combinator")
            return
          }
        }
        continue loop
      default:
        break
      }

      let (canElideNamespace, firstNonNamespace) =
        switch compound[0] {
        case .explicitAnyNamespace, .explicitNoNamespace, .namespace: (false, 1)
        case .defaultNamespace: (true, 1)
        default: (true, 0)
        }
      var performStep2 = true
      let nextCombinator: Combinator? = combinators.next()

      if firstNonNamespace == compound.count - 1 {
        switch (nextCombinator, compound[firstNonNamespace]) {
        case (.pseudoElement, _), (.slotAssignment, _): break
        case (_, .explicitUniversalType):
          for simple in compound {
            simple.toCSS(to: &dest)
          }
          performStep2 = false
        default:
          break
        }
      }

      if performStep2 {
        for simple in compound {
          if case .explicitUniversalType = simple {
            if canElideNamespace {
              continue loop
            }
          }
          simple.toCSS(to: &dest)
        }
      }
      if let nextCombinator {
        nextCombinator.toCSS(to: &dest)
      } else {
        combinatorsExhausted = true
      }
    }
  }
}

public enum MatchesFeaturelessHost: Equatable {
  case yes
  case only
  case never

  public var mayMatch: Bool {
    switch self {
    case .never: false
    default: true
    }
  }
}
