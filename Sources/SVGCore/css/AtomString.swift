import _CSSParser

struct AtomString: Equatable, RawRepresentable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension AtomString: ExpressibleByStringLiteral {
  init(stringLiteral value: String) {
    self = .init(rawValue: value)
  }
}

extension AtomString: From {
  typealias From = String
  static func from(_ string: String) -> Self {
    Self(rawValue: string)
  }
}

extension AtomString: Parse {
  static func parse(context: ParserContext, input: inout _CSSParser.Parser) -> Result<AtomString, CSSParseError> {
    switch input.expectString() {
    case .failure(let error):
      .failure(error.into())
    case .success(let string):
      .success(.init(rawValue: string))
    }
  }
}

extension AtomString: ToCSS {
  func toCSS(to dest: inout some TextOutputStream) {
    dest.write("\"")
    var writer = CssStringWriter(&dest)
    writer.write(self.rawValue)
    dest.write("\"")
  }
}
