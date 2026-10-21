import _CSSParser
import _SelectorParser

public protocol StaticAtomSet {
  static func get() -> [String: Int]?
}

public struct GenericAtomIdent<Static: StaticAtomSet>: Hashable {
  public let rawValue: String
  public let index: Int?

  public init(rawValue: String) {
    self.rawValue = rawValue
    self.index = Static.get()?[rawValue]
  }
}

extension GenericAtomIdent: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.index, rhs.index) {
    case (.some(let lhs), .some(let rhs)): return lhs == rhs
    case (.none, .none): return lhs.rawValue == rhs.rawValue
    default: return false
    }
  }
}

extension GenericAtomIdent: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    serializeIdentifier(rawValue, dest: &dest)
  }
}

extension GenericAtomIdent: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .init(rawValue: value)
  }
}

extension GenericAtomIdent: From {
  public typealias From = String
  public static func from(_ string: String) -> Self {
    Self(rawValue: string)
  }
}

extension GenericAtomIdent: Default {
  public static func `default`() -> GenericAtomIdent<Static> {
    Self(rawValue: "")
  }
}
