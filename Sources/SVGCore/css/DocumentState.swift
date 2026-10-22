struct DocumentState: OptionSet, Sendable {
  let rawValue: UInt64
  init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  static let empty: Self = []

  static let windowInactive = Self(rawValue: 1 << 0)
  static let rtlLocale = Self(rawValue: 1 << 1)
  static let ltrLocale = Self(rawValue: 1 << 2)
  static let allLocaledirBits: Self = [.ltrLocale, .rtlLocale]
}
