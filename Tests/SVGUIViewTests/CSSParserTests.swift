import XCTest
import _CSSParser

@testable import SVGUIView

struct TestData<T: Codable>: Codable {
  let src: String
  let want: T
}

final class CSSParserTests: XCTestCase {
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  private func parseDeclaration(src: String) -> Result<CSSDeclaration, StyleParseErrorKind> {
    let parseInput = ParserInput(input: src)
    var input = Parser(input: parseInput)
    var parser = CSSDeclarationParser()
    switch parseOneDeclaration(input: &input, parser: &parser) {
    case .success(let decl):
      return .success(decl)
    case .failure(let err):
      fatalError(err.localizedDescription)
    }
  }

  private func parseRule(src: String) -> CSSRule {
    let parseInput = ParserInput(input: src)
    var input = Parser(input: parseInput)
    var parser = CSSParser(input: input)
    return try! parseOneRule(input: &input, parser: &parser).get()
  }

  func testDeclarationList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "declaration_list", withExtension: "json")!)
    let tests = try Self.decoder.decode([TestData<CSSDeclaration>].self, from: Data(json.utf8))
    for test in tests {
      let result = try parseDeclaration(src: test.src).get()
      XCTAssertEqual(result, test.want)
    }
  }

  func testOneRule() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "one_rule", withExtension: "json")!)
    let tests = try Self.decoder.decode([TestData<CSSRule>].self, from: Data(json.utf8))
    for test in tests {
      let rule = parseRule(src: test.src)
      XCTAssertEqual(rule, test.want)
    }
  }
}
