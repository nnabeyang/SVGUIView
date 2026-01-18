public enum MatchingMode: Equatable {
  case normal
  case forStatelessPseudoElement
}

public struct MatchingContext<Impl: SelectorImpl> {
  var matchingMode: MatchingMode
  public var bloomFilter: BloomFilter?
  var nestingLevel: Int
  var inNegation: Bool
  public let classesAndIdsCaseSensitivity: CaseSensitivity
  public var featureless: Bool = false
  public var quirksMode: QuirksMode = .quirks
  public var pseudoElementMatchingFn: ((Impl.PseudoElement) -> Bool)?
  public var isNested: Bool {
    nestingLevel > 0
  }

  public init(matchingMode: MatchingMode = .normal, bloomFilter: BloomFilter? = nil, nestingLevel: Int = 0, inNegation: Bool = false, classesAndIdsCaseSensitivity: CaseSensitivity = .asciiCaseInsensitive) {
    self.matchingMode = matchingMode
    self.bloomFilter = bloomFilter
    self.nestingLevel = nestingLevel
    self.inNegation = inNegation
    self.classesAndIdsCaseSensitivity = classesAndIdsCaseSensitivity
  }

  mutating public func withFeatureless<R>(featureless: Bool, _ f: (inout Self) throws -> R) rethrows -> R {
    let original = self.featureless
    self.featureless = featureless
    defer {
      self.featureless = original
    }
    return try f(&self)
  }
}

public enum QuirksMode: Equatable {
  case quirks
  case limitedQuirks
  case noQuirks

  public var classesAndIdsCaseSensitivity: CaseSensitivity {
    switch self {
    case .noQuirks, .limitedQuirks: .caseSensitive
    case .quirks: .asciiCaseInsensitive
    }
  }
}
