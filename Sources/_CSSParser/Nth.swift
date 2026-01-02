import Foundation

public func parseNth(input: inout Parser) -> Result<(Int32, Int32), BasicParseError> {
  switch input.next() {
  case .failure(let error):
    return .failure(error)
  case .success(let token):
    switch token {
    case .number(let number) where number.intValue != nil:
      return .success((0, number.intValue!))
    case .dimention(let dimension) where dimension.intValue != nil:
      let a = dimension.intValue!
      switch dimension.unit.lowercased() {
      case "n":
        return parseB(input: &input, a: a)
      case "n-":
        return parseSignlessB(input: &input, a: a, bSign: -1)
      default:
        let unit = dimension.unit
        if let b = parseNDashDigits(string: unit) {
          return .success((a, b))
        } else {
          return .failure(input.newBasicUnexpectedTokenError(token: .ident(unit)))
        }
      }
    case .ident(let value):
      switch value.lowercased() {
      case "even":
        return .success((2, 0))
      case "odd":
        return .success((2, 1))
      case "n":
        return parseB(input: &input, a: 1)
      case "-n":
        return parseB(input: &input, a: -1)
      case "n-":
        return parseSignlessB(input: &input, a: 1, bSign: -1)
      case "-n-":
        return parseSignlessB(input: &input, a: -1, bSign: -1)
      default:
        let (slice, a) =
          if let stripped = value.stripPrefix("-") {
            (stripped, Int32(-1))
          } else {
            (value, Int32(1))
          }
        if let b = parseNDashDigits(string: slice) {
          return .success((a, b))
        } else {
          return .failure(input.newBasicUnexpectedTokenError(token: .ident(value)))
        }
      }
    case .delim("+"):
      switch input.nextIncludingWhitespace() {
      case .failure(let error):
        return .failure(error)
      case .success(.ident(let value)):
        switch value.lowercased() {
        case "n": return parseB(input: &input, a: 1)
        case "n-": return parseSignlessB(input: &input, a: 1, bSign: -1)
        case let value:
          if let b = parseNDashDigits(string: value) {
            return .success((1, b))
          } else {
            return .failure(input.newBasicUnexpectedTokenError(token: .ident(value)))
          }
        }
      case .success(let token):
        return .failure(input.newBasicUnexpectedTokenError(token: token))
      }
    case let token:
      return .failure(input.newBasicUnexpectedTokenError(token: token))
    }
  }
}

func parseB(input: inout Parser, a: Int32) -> Result<(Int32, Int32), BasicParseError> {
  let start = input.state
  switch input.next() {
  case .success(.delim("+")): return parseSignlessB(input: &input, a: a, bSign: 1)
  case .success(.delim("-")): return parseSignlessB(input: &input, a: a, bSign: -1)
  case .success(.number(let number)) where number.intValue != nil:
    return .success((a, number.intValue!))
  default:
    input.reset(state: start)
    return .success((a, 0))
  }
}

func parseSignlessB(
  input: inout Parser,
  a: Int32,
  bSign: Int32
) -> Result<(Int32, Int32), BasicParseError> {
  switch input.next() {
  case .success(.number(let number)) where number.intValue != nil:
    return .success((a, bSign * number.intValue!))
  case .success(let token):
    return .failure(input.newBasicUnexpectedTokenError(token: token))
  case .failure(let error):
    return .failure(error)
  }
}

func parseNDashDigits(string: String) -> Int32? {
  let bytes = Data(string.utf8)
  if bytes.count >= 3
    && bytes[0..<2].isEqualAsciiCaseInsensitive(to: Data([UInt8(ascii: "n"), UInt8(ascii: "-")]))
    && bytes.allSatisfy(\.isASCIIDigit)
  {
    return parseNumberSaturate(string: String(string.dropFirst()))  // Include the minus sign
  } else {
    return nil
  }
}

func parseNumberSaturate(string: String) -> Int32? {
  let input = ParserInput(input: string)
  var parser = Parser(input: input)
  let intValue: Int32
  switch parser.nextIncludingWhitespaceAndComments() {
  case .success(.number(let number)) where number.intValue != nil:
    intValue = number.intValue!
  default:
    return nil
  }
  guard parser.isExhausted() else { return nil }
  return intValue
}

extension Data {
  func isEqualAsciiCaseInsensitive(to other: Data) -> Bool {
    if count != other.count { return false }
    return withUnsafeBytes { lhs in
      return other.withUnsafeBytes { rhs in
        let lhs = lhs.bindMemory(to: UInt8.self)
        let rhs = rhs.bindMemory(to: UInt8.self)

        for i in 0..<lhs.count {
          let a = lhs[i]
          let b = rhs[i]
          if !a.isEqualAsciiCaseInsensitive(b) { return false }
        }
        return true
      }
    }
  }
}

extension String {
  func stripPrefix(_ prefix: String) -> String? {
    guard self.hasPrefix(prefix) else {
      return nil
    }
    let start = self.index(self.startIndex, offsetBy: prefix.count)
    return String(self[start...])
  }
}

private let ASCII_CASE_MASK: UInt8 = 0x20
extension UInt8 {
  func isEqualAsciiCaseInsensitive(_ other: UInt8) -> Bool {
    toAsciiLowercase == other.toAsciiLowercase
  }

  var toAsciiLowercase: Self {
    self | (isAsciiUppercase ? ASCII_CASE_MASK : 0)
  }

  var isAsciiUppercase: Bool {
    (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
  }
}
