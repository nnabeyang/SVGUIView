import _CSSParser
import _SelectorParser

class ParserContext {
  var parsingMode: ParsingMode

  init(parsingMode: ParsingMode = .default) {
    self.parsingMode = parsingMode
  }
}

protocol Parse {
  static func parse(context: ParserContext, input: inout _CSSParser.Parser) -> Result<Self, CSSParseError>
}

typealias CSSParseError = ParseError<StyleParseErrorKind>
enum StyleParseErrorKind: Error, Equatable {
  case invalid
  case selectorError(SelectorParseErrorKind)
}

extension StyleParseErrorKind: From {
  typealias From = SelectorParseErrorKind
  static func from(_ kind: SelectorParseErrorKind) -> StyleParseErrorKind {
    .selectorError(kind)
  }
}
