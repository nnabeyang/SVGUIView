import _CSSParser

struct Space: Separator {
  func separator() -> String {
    " "
  }

  func parse<T, E>(input: inout Parser, parseOne: (inout Parser) -> Result<T, ParseError<E>>) -> Result<[T], ParseError<E>> where E: Equatable & Sendable {
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
