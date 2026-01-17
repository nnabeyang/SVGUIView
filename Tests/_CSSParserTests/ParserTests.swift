import Foundation
import Testing

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

func assertJSONEq(_ results: JSONValue, _ expected: JSONValue, message: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
  var expected = expected
  normalize(&expected)
  if !almostEquals(results, expected) {
    Issue.record("actual: \(results), expected: \(expected) input:\(message.debugDescription)", sourceLocation: sourceLocation)
  }
}

func runRawJSONTests(jsonData: String, run: @escaping (JSONValue, JSONValue) -> Void, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
  do {
    let items: [JSONValue] = try JSONDecoder().decode([JSONValue].self, from: Data(jsonData.utf8))
    #expect(items.count % 2 == 0, sourceLocation: sourceLocation)
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
    Issue.record("Invalid JSON: \(jsonData)", sourceLocation: sourceLocation)
  }
}

func runJSONTests(jsonData: String, parse: @escaping (inout Parser) -> JSONValue, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
  runRawJSONTests(jsonData: jsonData) { input, expected in
    switch input {
    case .string(let input):
      let parseInput = ParserInput(input: input)
      var parser = Parser(input: parseInput)
      let result = parse(&parser)
      assertJSONEq(result, expected, message: input, sourceLocation: sourceLocation)
    default:
      Issue.record("Unexpected JSON")
    }
  }
}

@Suite("Parser")
struct ParserTests {
  @Test("normalize updates arrays and strings as expected")
  func normalize() {
    var items: JSONValue = ["empty", "hello", "extra-input"]
    _CSSParserTests.normalize(&items)
    #expect(almostEquals(items, ["invalid", "hello", "invalid"]))
    var simple: JSONValue = "empty"
    _CSSParserTests.normalize(&simple)
    #expect(almostEquals(simple, "invalid"))
  }

  @Test("component value list parses to expected JSON")
  func componentValueList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "component_value_list", withExtension: "json")!)
    runJSONTests(jsonData: json) { input in
      .array(componentValueToJSON(input: &input))
    }
  }

  @Test("one component value parses or returns error JSON")
  func oneComponentValue() throws {
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

  @Test("declaration list parser yields items including errors")
  func declarationList() throws {
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

  @Test("one declaration parses or returns error JSON")
  func oneDeclaration() throws {
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

  @Test("one rule parses or returns error JSON")
  func oneRule() throws {
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

  @Test("rule list iterates and collects items")
  func ruleList() throws {
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

  @Test("stylesheet parses into array of items")
  func stylesheet() throws {
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

  @Test("parseUntilBefore stops at delimiter or end of input and matches sequences")
  func parseUntilBeforeStopsAtDelimiterOrEndOfInput() {
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
                #expect(ox == oy)
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

  @Test("parser maintains current line across tokens")
  func parserMaintainsCurrentLine() {
    let input = ParserInput(input: "ident ident;\nident ident ident;\nident")
    var parser = Parser(input: input)
    #expect(parser.currentLine() == "ident ident;")
    #expect(parser.next() == .success(.ident("ident")))
    #expect(parser.next() == .success(.ident("ident")))
    #expect(parser.next() == .success(.semicolon))

    #expect(parser.next() == .success(.ident("ident")))
    #expect(parser.currentLine() == "ident ident ident;")
    #expect(parser.next() == .success(.ident("ident")))
    #expect(parser.next() == .success(.ident("ident")))
    #expect(parser.next() == .success(.semicolon))

    #expect(parser.next() == .success(.ident("ident")))
    #expect(parser.currentLine() == "ident")
    #expect(parser.next() == .failure(.init(kind: .endOfInput, location: .init(line: 2, column: 6))))
  }

  @Test("CDC regression: skipCdcAndCdo then next() returns expected tokens")
  func cdcRegressionTest() {
    let input = ParserInput(input: "-->x")
    var parser = Parser(input: input)
    parser.skipCdcAndCdo()
    #expect(parser.next() == .success(.ident("x")))
    #expect(parser.next() == .failure(.init(kind: .endOfInput, location: .init(line: 0, column: 5))))
  }

  @Test("parseEntirely reports first custom error")
  func entirelyReportsFirstError() {
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
      Issue.record("unexpected result: \(result))")
      return
    }
    #expect(error == .init(kind: .custom(.foo), location: .init(line: 0, column: 1)))
  }

  @Test("parses sourcemapping comments and extracts URL")
  func parseSourcemappingComments() {
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
      #expect(parser.currentSourceMapUrl == test.1)
    }
  }

  @Test("percentage tokens roundtrip through parser")
  func roundtripPercentageToken() {
    func testRoundtrip(value: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
      let input = ParserInput(input: String(value))
      var parser = Parser(input: input)
      switch parser.next() {
      case .success(let token):
        #expect(token.toCSSString() == String(value), sourceLocation: sourceLocation)
      case .failure(let error):
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
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

  @Test("UTF16 column computation matches expected")
  func utf16Columns() {
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
      #expect(parser.currentSourceLocation.column == test.1)
    }
  }

  @Test("unquoted url escaping serializes as expected")
  func unquotedUrlEscaping() {
    let token = Token.unquotedUrl(
      [
        "\u{01}\u{02}\u{03}\u{04}\u{05}\u{06}\u{07}\u{08}\t\n\u{0b}\u{0c}\r\u{0e}\u{0f}\u{10}",
        "\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f} ",
        "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]",
        "^_`abcdefghijklmnopqrstuvwxyz{|}~\u{7f}é",
      ].joined())
    let serialized = token.toCSSString()
    #expect(
      serialized
        == [
          "url(",
          "\\1 \\2 \\3 \\4 \\5 \\6 \\7 \\8 \\9 \\a \\b \\c \\d \\e \\f \\10 ",
          "\\11 \\12 \\13 \\14 \\15 \\16 \\17 \\18 \\19 \\1a \\1b \\1c \\1d \\1e \\1f \\20 ",
          "!\\\"#$%&\\\'\\(\\)*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]",
          "^_`abcdefghijklmnopqrstuvwxyz{|}~\\7f é",
          ")",
        ].joined()
    )
  }

  @Test("unquoted url escaping basic case")
  func unquotedUrlEscaping2() {
    let token = Token.unquotedUrl("!\"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]")
    let serialized = token.toCSSString()
    #expect(serialized == "url(!\\\"#$%&\\\'\\(\\)*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[])")
  }

  @Test("expectUrl parses success and failure cases")
  func expectUrl() {
    func parse(_ src: String) -> Result<String, BasicParseError> {
      let input = ParserInput(input: src)
      var p = Parser(input: input)
      return p.expectUrl()
    }

    #expect(parse("url()") == .success(""))
    #expect(parse("url( ") == .success(""))
    #expect(parse("url( abc") == .success("abc"))
    #expect(parse("url( abc \t)") == .success("abc"))
    #expect(parse("url( 'abc' \t)") == .success("abc"))
    #expect(parse("url(abc more stuff)") == .failure(.init(kind: .unexpectedToken(.badUrl("abc more stuff")), location: .init(line: 0, column: 1))))
  }
}
