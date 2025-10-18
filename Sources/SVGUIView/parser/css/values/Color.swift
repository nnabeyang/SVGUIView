import _CSSParser

extension SVGRGBAColor: Parse {
  static func parse(context: ParserContext, input: inout _CSSParser.Parser) -> Result<SVGRGBAColor, ParseError> {
    input.parseNestedBlock { input in
      do throws(ParseError) {
        let r = try Number.parse(context: context, input: &input).get().value
        try expectComma(input: &input)
        let g = try Number.parse(context: context, input: &input).get().value
        try expectComma(input: &input)
        let b = try Number.parse(context: context, input: &input).get().value
        try expectComma(input: &input)
        let a = try Number.parse(context: context, input: &input).get().value
        return .success(.init(r: .absolute(Double(r)), g: .absolute(Double(g)), b: .absolute(Double(b)), a: Double(a)))
      } catch {
        return .failure(error)
      }
    }
  }

  private static func expectComma(input: inout _CSSParser.Parser) throws(ParseError) {
    guard case .failure(let error) = input.expectComma() else { return }
    throw .init(basic: error)
  }
}

extension SVGRGBColor: Parse {
  static func parse(context: ParserContext, input: inout _CSSParser.Parser) -> Result<SVGRGBColor, ParseError> {
    input.parseNestedBlock { input in
      do throws(ParseError) {
        let r = try Number.parse(context: context, input: &input).get().value
        try expectComma(input: &input)
        let g = try Number.parse(context: context, input: &input).get().value
        try expectComma(input: &input)
        let b = try Number.parse(context: context, input: &input).get().value
        return .success(.init(r: .absolute(Double(r)), g: .absolute(Double(g)), b: .absolute(Double(b))))
      } catch {
        return .failure(error)
      }
    }
  }

  private static func expectComma(input: inout _CSSParser.Parser) throws(ParseError) {
    guard case .failure(let error) = input.expectComma() else { return }
    throw .init(basic: error)
  }
}
