import Foundation
import XCTest

@testable import _CSSParser

func almostEquals(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
  switch (lhs, rhs) {
  case (.number(let lhs), .number(let rhs)):
    let lhs: Float64 = Float64(lhs)
    let rhs: Float64 = Float64(rhs)
    return abs(lhs - rhs) <= abs(lhs) * 1e-6
  case (.bool(let lhs), .bool(let rhs)):
    return lhs == rhs
  case (.string(let lhs), .string(let rhs)):
    return lhs == rhs
  case (.array(let lhs), .array(let rhs)):
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy({ (lhs, rhs) in almostEquals(lhs, rhs) })
  case (.object, .object): fatalError("Not implemented")
  case (.null, .null): return true
  default:
    return false
  }
}

func normalize(_ json: inout JSONValue) {
  switch json {
  case .array(var array):
    for (index, var item) in array.enumerated() {
      normalize(&item)
      array[index] = item
    }
    json = .array(array)
  case .string(let s):
    if s == "extra-input" || s == "empty" {
      json = .string("invalid")
    }
  default:
    break
  }
}

func assertJSONEq(_ results: JSONValue, _ expected: JSONValue, message: String, file: StaticString = #filePath, line: UInt = #line) {
  var expected = expected
  normalize(&expected)
  if !almostEquals(results, expected) {
    XCTFail("actual: \(results), expected: \(expected) input:\(message.debugDescription)", file: file, line: line)
  }
}

func runRawJSONTests(jsonData: String, run: @escaping (JSONValue, JSONValue) -> Void, file: StaticString = #filePath, line: UInt = #line) {
  do {
    let items: [JSONValue] = try JSONDecoder().decode([JSONValue].self, from: Data(jsonData.utf8))
    XCTAssertTrue(items.count % 2 == 0, file: file, line: line)
    var input: JSONValue? = nil
    for item in items {
      switch (input, item) {
      case (.none, let jsonObj):
        input = jsonObj
      case (.some(let src), let expected):
        run(src, expected)
        input = nil
      }
    }
  } catch {
    XCTFail("Invalid JSON: \(jsonData)")
  }
}

func runJSONTests(jsonData: String, parse: @escaping (inout Parser) -> JSONValue, file: StaticString = #filePath, line: UInt = #line) {
  runRawJSONTests(jsonData: jsonData) { input, expected in
    switch input {
    case .string(let input):
      let parseInput = ParserInput(input: input)
      var parser = Parser(input: parseInput)
      let result = parse(&parser)
      assertJSONEq(result, expected, message: input, file: file, line: line)
    default:
      XCTFail("Unexpected JSON")
    }
  }
}

final class ParserTests: XCTestCase {
  func testNormalize() {
    var items: JSONValue = ["empty", "hello", "extra-input"]
    normalize(&items)
    XCTAssertTrue(almostEquals(items, ["invalid", "hello", "invalid"]))
    var simple: JSONValue = "empty"
    normalize(&simple)
    XCTAssertTrue(almostEquals(simple, "invalid"))
  }

  func testComponentValueList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "component_value_list", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      .array(componentValueToJSON(input: &input))
    }
  }

  func testOneComponentValue() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "one_component_value", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      let result: Result<JSONValue, ParseError<DummyError>> = input.parseEntirely { input in
        switch input.next() {
        case .success(let token):
          return .success(oneComponentValueToJSON(token: token, input: &input))
        case .failure(let error):
          return .failure(.init(basic: error))
        }
      }
      switch result {
      case .success(let value):
        return value
      case .failure:
        return ["error", "invalid"]
      }
    }
  }

  func testDeclarationList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "declaration_list", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      let parser: RuleBodyParser<JSONParser, JSONValue, JSONError> = RuleBodyParser(input: input, parser: JSONParser())
      var items: [JSONValue] = []
      for element in parser {
        switch element {
        case .success(let value):
          items.append(value)
        case .failure:
          items.append(["error", "invalid"])
        }
      }
      return .array(items)
    }
  }

  func testOneDeclaration() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "one_declaration", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      var parser = JSONParser()
      let result = parseOneDeclaration(input: &input, parser: &parser)
      switch result {
      case .success(let value):
        return value
      case .failure:
        return ["error", "invalid"]
      }
    }
  }

  func testOneRule() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "one_rule", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      var parser = JSONParser()
      let result = parseOneRule(input: &input, parser: &parser)
      switch result {
      case .success(let value):
        return value
      case .failure:
        return ["error", "invalid"]
      }
    }
  }

  func testRuleList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "rule_list", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      var parser: RuleBodyParser<JSONParser, JSONValue, JSONError> = RuleBodyParser(input: input, parser: JSONParser())
      var items: [JSONValue] = []
      while let element = parser.next() {
        switch element {
        case .success(let value):
          items.append(value)
        case .failure:
          items.append(["error", "invalid"])
        }
      }
      return .array(items)
    }
  }

  func testStylesheet() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "stylesheet", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      var jsonParser = JSONParser()
      let parser = StyleSheetParser(input: input, parser: &jsonParser)
      var items: [JSONValue] = []
      for element in parser {
        switch element {
        case .success(let value):
          items.append(value)
        case .failure:
          items.append(["error", "invalid"])
        }
      }
      return .array(items)
    }
  }

  func testParseUntilBeforeStopsAtDelimiterOrEndOfInput() {
    let inputs: [(Delimiters, [String])] = [
      ([.bang, .semicolon], ["token stream;extra", "token stream!", "token stream"]),
      ([.bang, .semicolon], [";", "!", ""]),
    ]

    for equivalent in inputs {
      for (j, x) in equivalent.1.enumerated() {
        for y in equivalent.1.dropFirst(j + 1) {
          let x = ParserInput(input: x)
          var ix = Parser(input: x)
          let y = ParserInput(input: y)
          var iy = Parser(input: y)
          let _: Result<Void, ParseError<Never>> = ix.parseUntilBefore(delimiters: equivalent.0) { ix in
            iy.parseUntilBefore(delimiters: equivalent.0) { iy in
              while true {
                let ox = ix.next()
                let oy = iy.next()
                XCTAssertEqual(ox, oy)
                if case .failure = ox {
                  break
                }
              }
              return .success(())
            }
          }
        }
      }
    }
  }

  func testParserMaintainsCurrentLine() {
    let input = ParserInput(input: "ident ident;\nident ident ident;\nident")
    var parser = Parser(input: input)
    XCTAssertEqual(parser.currentLine(), "ident ident;")
    XCTAssertEqual(parser.next(), .success(.ident("ident")))
    XCTAssertEqual(parser.next(), .success(.ident("ident")))
    XCTAssertEqual(parser.next(), .success(.semicolon))

    XCTAssertEqual(parser.next(), .success(.ident("ident")))
    XCTAssertEqual(parser.currentLine(), "ident ident ident;")
    XCTAssertEqual(parser.next(), .success(.ident("ident")))
    XCTAssertEqual(parser.next(), .success(.ident("ident")))
    XCTAssertEqual(parser.next(), .success(.semicolon))

    XCTAssertEqual(parser.next(), .success(.ident("ident")))
    XCTAssertEqual(parser.currentLine(), "ident")
    XCTAssertEqual(parser.next(), .failure(.init(kind: .endOfInput, location: .init(line: 2, column: 6))))
  }

  func testCdcRegressionTest() {
    let input = ParserInput(input: "-->x")
    var parser = Parser(input: input)
    parser.skipCdcAndCdo()
    XCTAssertEqual(parser.next(), .success(.ident("x")))
    XCTAssertEqual(parser.next(), .failure(.init(kind: .endOfInput, location: .init(line: 0, column: 5))))
  }

  func testEntirelyReportsFirstError() {
    enum E: Error, Equatable, CustomStringConvertible {
      case foo

      var description: String {
        "foo"
      }
    }
    let input = ParserInput(input: "ident")
    var parser = Parser(input: input)
    let result: Result<Void, ParseError> = parser.parseEntirely { p in
      .failure(p.newCustomError(error: E.foo))
    }
    guard case .failure(let error) = result else {
      XCTFail("unexpected result: \(result))")
      return
    }
    XCTAssertEqual(error, .init(kind: .custom(.foo), location: .init(line: 0, column: 1)))
  }

  func testParseSourcemappingComments() {
    let tests: [(String, String?)] = [
      ("/*# sourceMappingURL=here*/", .some("here")),
      ("/*# sourceMappingURL=here  */", .some("here")),
      ("/*@ sourceMappingURL=here*/", .some("here")),
      (
        "/*@ sourceMappingURL=there*/ /*# sourceMappingURL=here*/",
        .some("here"),
      ),
      ("/*# sourceMappingURL=here there  */", .some("here")),
      ("/*# sourceMappingURL=  here  */", .some("")),
      ("/*# sourceMappingURL=*/", .some("")),
      ("/*# sourceMappingUR=here  */", .none),
      ("/*! sourceMappingURL=here  */", .none),
      ("/*# sourceMappingURL = here  */", .none),
      ("/*   # sourceMappingURL=here   */", .none),
    ]
    for test in tests {
      let input = ParserInput(input: test.0)
      var parser = Parser(input: input)
      while true {
        if case .failure = parser.nextIncludingWhitespace() {
          break
        }
      }
      XCTAssertEqual(parser.currentSourceMapUrl, test.1, test.0.debugDescription)
    }
  }

  func testRoundtripPercentageToken() {
    func testRoundtrip(value: String, file: StaticString = #filePath, line: UInt = #line) {
      let input = ParserInput(input: String(value))
      var parser = Parser(input: input)
      switch parser.next() {
      case .success(let token):
        XCTAssertEqual(token.toCSSString(), String(value), file: file, line: line)
      case .failure(let error):
        XCTFail("Unexpected error: \(error)", file: file, line: line)
      }
    }

    for i in 0...100 {
      testRoundtrip(value: "\(i)%")
      if i == 100 {
        break
      }
      for j in 0..<10 {
        if j != 0 {
          testRoundtrip(value: "\(i).\(j)%")
        }
        for k in 1..<10 {
          testRoundtrip(value: "\(i).\(j)\(k)%")
        }
      }
    }
  }

  func testUTF16Columns() {
    let tests: [(String, Int)] = [
      ("", 1),
      ("ascii", 6),
      ("/*QΡ✈🆒*/", 10),
      ("'QΡ✈🆒*'", 9),
      ("\"\\\"'QΡ✈🆒*'", 12),
      ("\\Q\\Ρ\\✈\\🆒", 10),
      ("QΡ✈🆒", 6),
      ("QΡ✈🆒\\Q\\Ρ\\✈\\🆒", 15),
      ("newline\r\nQΡ✈🆒", 6),
      ("url(QΡ✈🆒\\Q\\Ρ\\✈\\🆒)", 20),
      ("url(QΡ✈🆒)", 11),
      ("url(\r\nQΡ✈🆒\\Q\\Ρ\\✈\\🆒)", 16),
      ("url(\r\nQΡ✈🆒\\Q\\Ρ\\✈\\🆒", 15),
      ("url(\r\nQΡ✈🆒\\Q\\Ρ\\✈\\🆒 x", 17),
      ("QΡ✈🆒()", 8),
      ("🆒", 3),
    ]

    for test in tests {
      let input = ParserInput(input: test.0)
      var parser = Parser(input: input)
      loop: while true {
        switch parser.next() {
        case .failure(let error):
          if case .endOfInput = error.kind {
            break loop
          }
          fatalError("unreachable")
        case .success:
          break
        }
      }
      XCTAssertEqual(parser.currentSourceLocation.column, test.1)
    }
  }

  func testUnquotedUrlEscaping() {
    let token = Token.unquotedUrl(
      [
        "\u{01}\u{02}\u{03}\u{04}\u{05}\u{06}\u{07}\u{08}\t\n\u{0b}\u{0c}\r\u{0e}\u{0f}\u{10}",
        "\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f} ",
        "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]",
        "^_`abcdefghijklmnopqrstuvwxyz{|}~\u{7f}é",
      ].joined())
    let serialized = token.toCSSString()
    XCTAssertEqual(
      serialized,
      [
        "url(",
        "\\1 \\2 \\3 \\4 \\5 \\6 \\7 \\8 \\9 \\a \\b \\c \\d \\e \\f \\10 ",
        "\\11 \\12 \\13 \\14 \\15 \\16 \\17 \\18 \\19 \\1a \\1b \\1c \\1d \\1e \\1f \\20 ",
        "!\\\"#$%&\\\'\\(\\)*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]",
        "^_`abcdefghijklmnopqrstuvwxyz{|}~\\7f é",
        ")",
      ].joined())
  }
  func testUnquotedUrlEscaping2() {
    let token = Token.unquotedUrl("!\"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]")
    let serialized = token.toCSSString()
    XCTAssertEqual(serialized, "url(!\\\"#$%&\\\'\\(\\)*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[])")
  }

  func testExpectUrl() {
    func parse(_ src: String) -> Result<String, BasicParseError> {
      let input = ParserInput(input: src)
      var p = Parser(input: input)
      return p.expectUrl()
    }

    XCTAssertEqual(parse("url()"), .success(""))
    XCTAssertEqual(parse("url( "), .success(""))
    XCTAssertEqual(parse("url( abc"), .success("abc"))
    XCTAssertEqual(parse("url( abc \t)"), .success("abc"))
    XCTAssertEqual(parse("url( 'abc' \t)"), .success("abc"))
    XCTAssertEqual(parse("url(abc more stuff)"), .failure(.init(kind: .unexpectedToken(.badUrl("abc more stuff")), location: .init(line: 0, column: 1))))
  }
}
