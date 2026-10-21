import _CSSParser
import _SelectorParser

public class ParserContext {
  var parsingMode: ParsingMode

  init(parsingMode: ParsingMode = .default) {
    self.parsingMode = parsingMode
  }
}

protocol Parse {
  static func parse(context: ParserContext, input: inout _CSSParser.Parser) -> Result<Self, CSSParseError>
}

typealias CSSParseError = ParseError<StyleParseErrorKind>
public enum StyleParseErrorKind: Error, Equatable {
  case invalid
  case selectorError(SelectorParseErrorKind)
}

extension StyleParseErrorKind: From {
  public typealias From = SelectorParseErrorKind
  public static func from(_ kind: SelectorParseErrorKind) -> StyleParseErrorKind {
    .selectorError(kind)
  }
}
