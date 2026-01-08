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
}
