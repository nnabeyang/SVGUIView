@testable import _CSSParser

// The values of the cases of the tokens that the tests check, so that `#require` can take them.

extension Token {
  /// The number, or `nil` for another token.
  var number: Token.Number? {
    if case .number(let number) = self { number } else { nil }
  }

  /// The percentage, or `nil` for another token.
  var percentage: Token.Percentage? {
    if case .percentage(let percentage) = self { percentage } else { nil }
  }

  /// The dimension, or `nil` for another token.
  var dimention: Token.Dimention? {
    if case .dimention(let dimention) = self { dimention } else { nil }
  }
}
