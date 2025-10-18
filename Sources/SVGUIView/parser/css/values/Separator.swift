import _CSSParser

public protocol Separator {
  func separator() -> String
  func parse<T, E>(input: inout _CSSParser.Parser, parseOne: (inout _CSSParser.Parser) -> Result<T, _CSSParser.ParseError<E>>) -> Result<[T], _CSSParser.ParseError<E>>
}
