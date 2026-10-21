public struct DocumentState: OptionSet, Sendable {
  public let rawValue: UInt64
  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static let empty: Self = []

  public static let windowInactive = Self(rawValue: 1 << 0)
  public static let rtlLocale = Self(rawValue: 1 << 1)
  public static let ltrLocale = Self(rawValue: 1 << 2)
  public static let allLocaledirBits: Self = [.ltrLocale, .rtlLocale]
}
