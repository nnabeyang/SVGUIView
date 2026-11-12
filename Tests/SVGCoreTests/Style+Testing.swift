@testable import SVGCore

// The values of the cases of the style values that the tests check, so that `#require` can take them.

extension Declared {
  /// The value, or `nil` for a keyword such as `inherit`.
  var value: Value? {
    if case .value(let value) = self { value } else { nil }
  }
}

extension Paint {
  /// The color, or `nil` for another paint.
  var color: SVGColor? {
    if case .color(let color) = self { color } else { nil }
  }
}

extension ColorValue {
  /// The color, or `nil` for `currentColor` or an expression.
  var color: SVGColor? {
    if case .color(let color) = self { color } else { nil }
  }
}

extension SVGLength {
  /// Whether the length is a math function that's resolved where it's used.
  var isCalc: Bool {
    if case .calc = self { true } else { false }
  }
}

extension Declared {
  /// Whether the declaration is `inherit`.
  var isInherit: Bool {
    if case .inherit = self { true } else { false }
  }
}
