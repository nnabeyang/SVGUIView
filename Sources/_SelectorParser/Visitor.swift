public struct SelectorListKind: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let none = Self([])

  public static let negation = Self(rawValue: 1 << 0)
  public static let `is` = Self(rawValue: 1 << 1)
  public static let `where` = Self(rawValue: 1 << 2)
  public static let nthOf = Self(rawValue: 1 << 3)
  public static let has = Self(rawValue: 1 << 4)

  public init<Impl: SelectorImpl>(from component: Component<Impl>) {
    self =
      switch component {
      case .negation: .negation
      case .is: .is
      case .where: .where
      case .nthOf: .nthOf
      default: .none
      }
  }

  public var inNegation: Bool {
    contains(.negation)
  }

  public var inIs: Bool {
    contains(.is)
  }

  public var inWhere: Bool {
    contains(.where)
  }

  public var inNthOf: Bool {
    contains(.nthOf)
  }

  public var inHas: Bool {
    contains(.has)
  }

  public var relevantToNthOfDependencies: Bool {
    inNthOf && !inHas
  }
}
