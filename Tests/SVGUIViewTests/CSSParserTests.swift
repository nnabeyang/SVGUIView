import XCTest

@testable import SVGUIView

enum Result<Success, Failure> {
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
    encoder.outputFormatting = .prettyPrinted
    return encoder
  }()

  private static let decoder = JSONDecoder()

  private func parseTokens(src: String) -> [CSSToken] {
    var data = src
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var tokenizer = CSSTopTokenizer(bytes: bytes)
      var tokens = [CSSToken]()
      while true {
        let token = tokenizer.nextToken()
        if case .eof = token {
          break
        }
        tokens.append(token)
      }
      return tokens
    }
  }

  private func parseDeclarations(src: String) -> [Result<CSSDeclaration, CSSParseError>] {
    var data = src
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var parser = CSSParser(bytes: bytes)
      var results = [Result<CSSDeclaration, CSSParseError>]()
      var tokenizer = parser.tokenizer
      while true {
        switch tokenizer.peek() {
        case .ident:
          let startIndex = tokenizer.readIndex
          tokenizer.consumeUntilSemicolon()
          var declaration = tokenizer.makeSubTokenizer(startIndex: startIndex, endIndex: tokenizer.readIndex)
          let result = parser.parseDeclaration(tokenizer: &declaration)
          switch result {
          case .success(let v):
            results.append(.success(v))
          case .failure(let e):
            results.append(.failure(e))
          }
        default:
          return results
        }
      }
    }
  }

  private func parseRule(src: String) -> CSSRule {
    var data = src
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var parser = CSSParser(bytes: bytes)
      return parser.parseRule()
    }
  }

  func testComponentValueList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "component_value_list", withExtension: "json")!)
    let tests = try Self.decoder.decode([TestData<[CSSToken]>].self, from: Data(json.utf8))
    for test in tests {
      let tokens = parseTokens(src: test.src)
      XCTAssertEqual(tokens, test.want)
    }
  }

  func testDeclarationList() throws {
    let json = try String(contentsOf: Bundle.module.url(forResource: "declaration_list", withExtension: "json")!)
    let tests = try Self.decoder.decode([TestData<[Result<CSSDeclaration, CSSParseError>]>].self, from: Data(json.utf8))
    for test in tests {
      let results = parseDeclarations(src: test.src)
      XCTAssertEqual(results, test.want)
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
