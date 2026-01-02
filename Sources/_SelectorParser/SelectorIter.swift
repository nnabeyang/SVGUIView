public struct SelectorIter<Impl: SelectorImpl> {
  var components: any BidirectionalCollection<Component<Impl>>
  private(set) var iter: any IteratorProtocol<Component<Impl>>
  var nextCombinator: Combinator?

  public init(components: any BidirectionalCollection<Component<Impl>>, nextCombinator: Combinator? = nil) {
    self.components = components
    self.iter = components.makeIterator()
    self.nextCombinator = nextCombinator
  }

  public mutating func nextSequence() -> Combinator? {
    let combinator = self.nextCombinator
    nextCombinator = nil
    return combinator
  }

  public mutating func matchesForStatelessPseudoElement() -> Bool {
    let first: Element
    switch next() {
    case .some(let c):
      first = c
    case .none:
      return true
    }
    return matchesForStatelessPseudoElementInternal(first)
  }

  mutating func matchesForStatelessPseudoElementInternal(_ first: Component<Impl>) -> Bool {
    guard first.matchesForStatelessPseudoElement() else {
      return false
    }
    while let component = next() {
      if !component.matchesForStatelessPseudoElement() {
        return false
      }
    }
    return true
  }

  var selectorLength: Int {
    components.count
  }
}

extension SelectorIter: IteratorProtocol {
  public typealias Element = Component<Impl>

  mutating public func next() -> Element? {
    assert(nextCombinator == nil, "You should call next_sequence!")
    switch iter.next() {
    case .combinator(let combinator):
      self.nextCombinator = combinator
      return nil
    case let x:
      return x
    }
  }
}

extension SelectorIter: CustomDebugStringConvertible {
  public var debugDescription: String {
    var s = ""
    for component in components.reversed() {
      component.toCSS(to: &s)
    }
    return s
  }
}

struct CombinatorIter<Impl: SelectorImpl> {
  var inner: SelectorIter<Impl>

  static func create(inner: SelectorIter<Impl>) -> Self {
    var result = CombinatorIter(inner: inner)
    result.consumeNonCombinators()
    return result
  }

  mutating func consumeNonCombinators() {
    while inner.next() != nil {}
  }
}

extension CombinatorIter: IteratorProtocol {
  typealias Element = Combinator

  mutating func next() -> Element? {
    let result = inner.nextSequence()
    consumeNonCombinators()
    return result
  }
}
