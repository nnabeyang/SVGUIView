import _CSSParser

struct ParsingMode: OptionSet {
  public let rawValue: UInt8
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  static let `default` = Self([])
  static let allowUnitlessLength = Self(rawValue: 1 << 0)
  static let allowAllNumericValues = Self(rawValue: 1 << 1)
  static let disallowComputationallyDependent = Self(rawValue: 1 << 2)

  func allowsAllNumericValues() -> Bool {
    (rawValue & Self.allowAllNumericValues.rawValue) != 0
  }
}

enum AllowedNumericType {
  case all
  case nonnegative
  case atLeastOne
  case zeroToOne

  func isOK(parsingMode: ParsingMode, value: Float32) -> Bool {
    if parsingMode.allowsAllNumericValues() {
      return true
    }
    switch self {
    case .all: return true
    case .nonnegative: return value >= 0.0
    case .atLeastOne: return value >= 1.0
    case .zeroToOne: return value >= 0.0 && value <= 1.0
    }
  }
}

struct Number {
  let value: Float32
  let calcClampingMode: AllowedNumericType?
}

/// Parse a `<number>` value, with a given clamping mode.
func parseNumberWithClampingMode(context: ParserContext, input: inout Parser, clampingMode: AllowedNumericType) -> Result<Number, CSSParseError> {
  let location = input.currentSourceLocation
  let result = input.next()
  if case .failure(let error) = result {
    return .failure(.init(basic: error))
  }
  let token = try! result.get()
  switch token {
  case .number(let value):
    if clampingMode.isOK(parsingMode: context.parsingMode, value: value.value) {
      return .success(.init(value: value.value, calcClampingMode: nil))
    }
  default:
    break
  }
  return .failure(location.newUnexpectedTokenError(token: token))
}

extension Number: Parse {
  static func parse(context: ParserContext, input: inout Parser) -> Result<Number, CSSParseError> {
    parseNumberWithClampingMode(context: context, input: &input, clampingMode: .all)
  }
}
