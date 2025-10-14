struct FontSelectionValue {
  static let fractionalEntropy: Int16 = 4
  let backing: Int16

  init(backing: Int16 = 0) {
    self.backing = backing
  }

  init(_ x: Int) {
    backing = Self.fractionalEntropy &* Int16(x)
  }

  init(_ x: Double) {
    backing = Self.fractionalEntropy &* Int16(x)
  }

  var double: Double { Double(backing) / Double(Self.fractionalEntropy) }

  static var zero: FontSelectionValue { .init() }

  static var minimumValue: FontSelectionValue { .init(backing: Int16.min) }

  static var maximumValue: FontSelectionValue { .init(backing: Int16.max) }

  static var italicValue: FontSelectionValue { .init(backing: 14) }

  static var normalItalicValue: FontSelectionValue { .zero }

  static var normalWeightValue: FontSelectionValue { .init(400) }

  static var normalStretchValue: FontSelectionValue { .init(100) }

  static var italicThreshold: FontSelectionValue { .init(14) }

  static var boldThreshold: FontSelectionValue { .init(600) }

  static var lowerWeightSearchThreshold: FontSelectionValue { .init(400) }

  static var upperWeightSearchThreshold: FontSelectionValue { .init(500) }

  static func isItalic(slope: FontSelectionValue?) -> Bool {
    slope.flatMap { $0 >= italicThreshold } ?? false
  }

  static func isFontWeightBold(fontWeight: FontSelectionValue) -> Bool {
    fontWeight >= boldThreshold
  }
}

extension FontSelectionValue: CustomDebugStringConvertible {
  var debugDescription: String {
    "FontSelectionValue(backing:\(backing), double: \(double))"
  }
}

func + (lhs: FontSelectionValue, rhs: FontSelectionValue) -> FontSelectionValue {
  FontSelectionValue(backing: lhs.backing + rhs.backing)
}

func - (lhs: FontSelectionValue, rhs: FontSelectionValue) -> FontSelectionValue {
  FontSelectionValue(backing: lhs.backing - rhs.backing)
}

func * (lhs: FontSelectionValue, rhs: FontSelectionValue) -> FontSelectionValue {
  FontSelectionValue(backing: (lhs.backing * rhs.backing) / FontSelectionValue.fractionalEntropy)
}

func / (lhs: FontSelectionValue, rhs: FontSelectionValue) -> FontSelectionValue {
  FontSelectionValue(backing: lhs.backing * FontSelectionValue.fractionalEntropy / rhs.backing)
}

prefix func - (lhs: FontSelectionValue) -> FontSelectionValue {
  FontSelectionValue(backing: -lhs.backing)
}

extension FontSelectionValue: Comparable {
  static func < (lhs: FontSelectionValue, rhs: FontSelectionValue) -> Bool {
    lhs.double < rhs.double
  }
}

extension FontSelectionValue: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(backing)
  }
}
