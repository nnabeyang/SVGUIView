import XCTest
import _CSSParser

@testable import SVGUIView

enum Result<Success, Failure: Error> {
  case success(Success)
  case failure(Failure)
}

extension Result: Encodable where Success: Encodable, Failure: Encodable {
  func encode(to encoder: any Encoder) throws {
    switch self {
    case .success(let value):
      try value.encode(to: encoder)
    case .failure(let error):
      try error.encode(to: encoder)
    }
  }
}

extension Result: Decodable where Success: Decodable, Failure: Decodable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Success.self) {
      self = .success(value)
      return
    }
    if let value = try? container.decode(Failure.self) {
      self = .failure(value)
      return
    }
    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
  }
}

extension Result: Equatable where Success: Equatable, Failure: Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.success(let lhs), .success(let rhs)):
      return lhs == rhs
    case (.failure(let lhs), .failure(let rhs)):
      return lhs == rhs
    default:
      return false
    }
  }
}

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

  private func parseDeclaration(src: String) -> Result<CSSDeclaration, CSSParseError> {
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
    let tests = try Self.decoder.decode([TestData<Result<CSSDeclaration, CSSParseError>>].self, from: Data(json.utf8))
    for test in tests {
      let result = parseDeclaration(src: test.src)
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
