public enum Token: Sendable, Equatable {
  /// A [`<ident-token>`](https://drafts.csswg.org/css-syntax/#ident-token-diagram)
  case ident(String)

  /// A [`<at-keyword-token>`](https://drafts.csswg.org/css-syntax/#at-keyword-token-diagram)
  case atKeyword(String)

  /// A [`<hash-token>`](https://drafts.csswg.org/css-syntax/#hash-token-diagram) with the type flag set to "unrestricted"
  case hash(String)

  /// A [`<hash-token>`](https://drafts.csswg.org/css-syntax/#hash-token-diagram) with the type flag set to "id"
  case idHash(String)

  /// A [`<string-token>`](https://drafts.csswg.org/css-syntax/#string-token-diagram)
  case quotedString(String)

  /// A [`<url-token>`](https://drafts.csswg.org/css-syntax/#url-token-diagram)
  case unquotedUrl(String)

  /// A `<delim-token>`
  case delim(Character)

  /// A [`<number-token>`](https://drafts.csswg.org/css-syntax/#number-token-diagram)
  case number(Number)

  /// A [`<percentage-token>`](https://drafts.csswg.org/css-syntax/#percentage-token-diagram)
  case percentage(Percentage)

  /// A [`<dimension-token>`](https://drafts.csswg.org/css-syntax/#dimension-token-diagram)
  case dimention(Dimention)

  /// A [`<whitespace-token>`](https://drafts.csswg.org/css-syntax/#whitespace-token-diagram)
  case whitespace(String)

  /// A comment.
  case comment(String)

  /// A `:` `<colon-token>`
  case colon  // :

  /// A `;` `<semicolon-token>`
  case semicolon  // ;

  /// A `,` `<comma-token>`
  case comma  // ,

  /// A `~=` [`<include-match-token>`](https://drafts.csswg.org/css-syntax/#include-match-token-diagram)
  case includeMatch

  /// A `|=` [`<dash-match-token>`](https://drafts.csswg.org/css-syntax/#dash-match-token-diagram)
  case dashMatch

  /// A `^=` [`<prefix-match-token>`](https://drafts.csswg.org/css-syntax/#prefix-match-token-diagram)
  case prefixMatch

  /// A `$=` [`<suffix-match-token>`](https://drafts.csswg.org/css-syntax/#suffix-match-token-diagram)
  case suffixMatch

  /// A `*=` [`<substring-match-token>`](https://drafts.csswg.org/css-syntax/#substring-match-token-diagram)
  case substringMatch

  /// A `<!--` [`<CDO-token>`](https://drafts.csswg.org/css-syntax/#CDO-token-diagram)
  case cdo

  /// A `-->` [`<CDC-token>`](https://drafts.csswg.org/css-syntax/#CDC-token-diagram)
  case cdc

  /// A [`<function-token>`](https://drafts.csswg.org/css-syntax/#function-token-diagram)
  case function(String)

  /// A `<(-token>`
  case parenthesisBlock

  /// A `<[-token>`
  case squareBracketBlock

  /// A `<{-token>`
  case curlyBracketBlock

  /// A `<bad-url-token>`
  case badUrl(String)

  /// A `<bad-string-token>`
  case badString(String)

  /// A `<)-token>`
  case closeParenthesis

  /// A `<]-token>`
  case closeSquareBracket

  /// A `<}-token>`
  case closeCurlyBracket
}

extension Token {
  public struct Number: Sendable, Equatable {
    public let value: Float32
    public let intValue: Int32?
    public let hasSign: Bool

    public init(value: Float32, intValue: Int32?, hasSign: Bool) {
      self.value = value
      self.intValue = intValue
      self.hasSign = hasSign
    }
  }

  public struct Percentage: Sendable, Equatable {
    public let unitValue: Float32
    public let intValue: Int32?
    public let hasSign: Bool

    public init(unitValue: Float32, intValue: Int32?, hasSign: Bool) {
      self.unitValue = unitValue
      self.intValue = intValue
      self.hasSign = hasSign
    }
  }

  public struct Dimention: Sendable, Equatable {
    public let hasSign: Bool
    public let value: Float32
    public let intValue: Int32?
    public let unit: String

    public init(value: Float32, intValue: Int32?, hasSign: Bool, unit: String) {
      self.hasSign = hasSign
      self.value = value
      self.intValue = intValue
      self.unit = unit
    }
  }
}

extension Token {
  public var isParseError: Bool {
    switch self {
    case .badUrl, .badString, .closeParenthesis, .closeSquareBracket, .closeCurlyBracket:
      true
    default:
      false
    }
  }
}
