import _CSSParser

public struct AtomString: Equatable, RawRepresentable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension AtomString: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .init(rawValue: value)
  }
}

extension AtomString: From {
  public typealias From = String
  public static func from(_ string: String) -> Self {
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
  public func toCSS(to dest: inout some TextOutputStream) {
    dest.write("\"")
    var writer = CssStringWriter(&dest)
    writer.write(self.rawValue)
    dest.write("\"")
  }
}
