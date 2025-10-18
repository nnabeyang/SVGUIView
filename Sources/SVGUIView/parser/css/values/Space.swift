import _CSSParser

struct Space: Separator {
  func separator() -> String {
    " "
  }

  func parse<T, E>(input: inout _CSSParser.Parser, parseOne: (inout _CSSParser.Parser) -> Result<T, _CSSParser.ParseError<E>>) -> Result<[T], _CSSParser.ParseError<E>> where E: Equatable & Sendable {
    input.skipWhitespace()
    var result: [T]
    switch parseOne(&input) {
    case .success(let value):
      result = [value]
    case .failure(let error):
      return .failure(error)
    }
    while true {
      input.skipWhitespace()
      if case .success(let item) = input.tryParse(parseOne) {
        result.append(item)
      } else {
        return .success(result)
      }
    }
  }
}
