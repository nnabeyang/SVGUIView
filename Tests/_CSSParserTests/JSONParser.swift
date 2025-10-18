import Foundation

@testable import _CSSParser

struct JSONError: Error, Equatable, Sendable {}

struct JSONParser {}
extension JSONParser: DeclarationParser {
  typealias Error = JSONError
  typealias Declaration = JSONValue

  func parseValue(name: String, input: inout Parser, declarationStart: inout ParserState) -> Result<JSONValue, ParseError<JSONError>> {
    var value = [JSONValue]()
    var important = false
    loop: while true {
      let start = input.state
      if case .success(var token) = input.nextIncludingWhitespace() {
        if case (.delim("!")) = token {
          input.reset(state: start)
          if case .success = parseImportant(parser: &input), input.isExhausted() {
            important = true
            break loop
          }
          input.reset(state: start)
          token = try! input.nextIncludingWhitespace().get()
        }
        value.append(oneComponentValueToJSON(token: token, input: &input))
      } else {
        break loop
      }
    }
    return .success(["declaration", .string(name), .array(value), .bool(important)])
  }
}

extension JSONParser: AtRuleParser {
  typealias Prelude = [JSONValue]
  typealias AtRule = JSONValue

  mutating func parsePrelude(name: String, input: inout Parser) -> Result<Prelude, ParseError<Self.Error>> {
    let prelude: [JSONValue] = ["at-rule", .string(name), .array(componentValueToJSON(input: &input))]
    let input = input
    return matchIgnoreAsciiCase(name) { lowercased in
      switch lowercased {
      case "charset":
        return .failure(input.newError(kind: .atRuleInvalid(name)))
      default:
        return .success(prelude)
      }
    }
  }

  mutating func ruleWithoutBlock(prelude: Prelude, start _: ParserState) -> AtRule {
    var prelude = prelude
    prelude.append(.null)
    return .array(prelude)
  }

  mutating func parseBlock(prelude: Prelude, start _: ParserState, input: inout Parser) -> Result<AtRule, ParseError<Self.Error>> {
    var prelude = prelude
    prelude.append(.array(componentValueToJSON(input: &input)))
    return .success(.array(prelude))
  }
}

extension JSONParser: QualifiedRuleParser {
  typealias QualifiedRule = JSONValue

  mutating func parseQualifiedPrelude(input: inout Parser) -> Result<Prelude, ParseError<Self.Error>> {
    .success(componentValueToJSON(input: &input))
  }

  mutating func parseQualifiedBlock(prelude: Prelude, start _: ParserState, input: inout Parser) -> Result<QualifiedRule, ParseError<Self.Error>> {
    return .success(["qualified rule", .array(prelude), .array(componentValueToJSON(input: &input))])
  }
}

extension JSONParser: RuleBodyItemParser {
  func parseDeclarations() -> Bool { true }
  func parseQualified() -> Bool { true }
}

func componentValueToJSON(input: inout Parser) -> [JSONValue] {
  var values = [JSONValue]()
  while case .success(let token) = input.nextIncludingWhitespace() {
    values.append(oneComponentValueToJSON(token: token, input: &input))
  }
  return values
}

func oneComponentValueToJSON(token: Token, input: inout Parser) -> JSONValue {
  func numeric(value: Float32, intValue: Int32?, hasSign: Bool) -> [JSONValue] {
    [
      .string(
        Token.number(
          .init(
            value: value,
            intValue: intValue,
            hasSign: hasSign)
        )
        .toCSSString()),
      intValue.flatMap({ JSONValue.number(.init(n: .init(Int($0)))) }) ?? .number(.init(n: .float(Float64(value)))),
      intValue != nil ? "integer" : "number",
    ]
  }

  func nested(input: inout Parser) -> [JSONValue] {
    let result: Result<[JSONValue], ParseError<Never>> = input.parseNestedBlock { input in
      .success(componentValueToJSON(input: &input))
    }
    return try! result.get()
  }

  switch token {
  case .ident(let value): return ["ident", .string(value)]
  case .atKeyword(let value): return ["at-keyword", .string(value)]
  case .hash(let value): return ["hash", .string(value), "unrestricted"]
  case .idHash(let value): return ["hash", .string(value), "id"]
  case .quotedString(let value): return ["string", .string(value)]
  case .unquotedUrl(let value): return ["url", .string(value)]
  case .delim("\\"): return .string("\\")
  case .delim(let value): return .string(String(value))
  case .number(let number):
    var values: [JSONValue] = ["number"]
    values.append(contentsOf: numeric(value: number.value, intValue: number.intValue, hasSign: number.hasSign))
    return .array(values)
  case .percentage(let percentage):
    var values: [JSONValue] = ["percentage"]
    values.append(contentsOf: numeric(value: percentage.unitValue * 100, intValue: percentage.intValue, hasSign: percentage.hasSign))
    return .array(values)
  case .dimention(let dimension):
    var values: [JSONValue] = ["dimension"]
    values.append(contentsOf: numeric(value: dimension.value, intValue: dimension.intValue, hasSign: dimension.hasSign))
    values.append(.string(dimension.unit))
    return .array(values)
  case .whitespace: return .string(" ")
  case .comment: return .string("/**/")
  case .colon: return .string(":")
  case .semicolon: return .string(";")
  case .comma: return .string(",")
  case .includeMatch: return .string("~=")
  case .dashMatch: return .string("|=")
  case .prefixMatch: return .string("^=")
  case .suffixMatch: return .string("$=")
  case .substringMatch: return .string("*=")
  case .cdo: return .string("<!--")
  case .cdc: return .string("-->")
  case .function(let name):
    var values: [JSONValue] = ["function", .string(name)]
    values.append(contentsOf: nested(input: &input))
    return .array(values)
  case .parenthesisBlock:
    var values: [JSONValue] = ["()"]
    values.append(contentsOf: nested(input: &input))
    return .array(values)
  case .squareBracketBlock:
    var values: [JSONValue] = ["[]"]
    values.append(contentsOf: nested(input: &input))
    return .array(values)
  case .curlyBracketBlock:
    var values: [JSONValue] = ["{}"]
    values.append(contentsOf: nested(input: &input))
    return .array(values)
  case .badUrl: return ["error", "bad-url"]
  case .badString: return ["error", "bad-string"]
  case .closeParenthesis: return ["error", ")"]
  case .closeSquareBracket: return ["error", "]"]
  case .closeCurlyBracket: return ["error", "}"]
  }
}
