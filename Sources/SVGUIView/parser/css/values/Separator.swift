import _CSSParser

public protocol Separator {
  func separator() -> String
  func parse<T, E>(input: inout Parser, parseOne: (inout Parser) -> Result<T, ParseError<E>>) -> Result<[T], ParseError<E>>
}
