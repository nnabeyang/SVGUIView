import _CSSParser

public class ParserContext {
  var parsingMode: ParsingMode

  init(parsingMode: ParsingMode = .default) {
    self.parsingMode = parsingMode
  }
}

protocol Parse {
  static func parse(context: ParserContext, input: inout _CSSParser.Parser) -> Result<Self, ParseError>
}

typealias ParseError = _CSSParser.ParseError<StyleParseErrorKind>
enum StyleParseErrorKind: Error, Equatable {}
