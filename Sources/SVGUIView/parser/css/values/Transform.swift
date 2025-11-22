import Foundation
import _CSSParser

extension CGAffineTransform: Parse {
  static func parse(context: ParserContext, input: inout Parser) -> Result<CGAffineTransform, CSSParseError> {
    if case .success = input.tryParse({ input in
      input.expectIdentMatching(expectedValue: "none")
    }) {
      return .success(.identity)
    }
    let result: Result<[any TransformOperator], CSSParseError> = Space().parse(input: &input) { input in
      let function: String
      switch input.expectFunction() {
      case .success(let string):
        function = string
      case .failure(let error):
        return .failure(.init(basic: error))
      }
      guard let type = TransformType(rawValue: function.lowercased()) else { return .failure(.init(basic: input.newBasicError(kind: .qualifiedRuleInvalid))) }
      return input.parseNestedBlock(parse: { input in
        do throws(CSSParseError) {
          switch type {
          case .scale:
            let x = try Number.parse(context: context, input: &input).get().value
            guard expectComma(input: &input) else {
              return .success(ScaleOperator(x: Double(x), y: Double(x)))
            }
            let y = try Number.parse(context: context, input: &input).get().value
            return .success(ScaleOperator(x: Double(x), y: Double(y)))
          case .translate:
            let x = try Number.parse(context: context, input: &input).get().value
            guard expectComma(input: &input) else {
              return .success(TranslateOperator(x: Double(x), y: Double(x)))
            }
            let y = try Number.parse(context: context, input: &input).get().value
            return .success(TranslateOperator(x: Double(x), y: Double(y)))
          case .rotate:
            let angle = try Number.parse(context: context, input: &input).get().value
            return .success(RotateOperator(angle: Double(angle), origin: nil))
          case .skewX:
            let angle = try Number.parse(context: context, input: &input).get().value
            return .success(SkewXOperator(angle: Double(angle)))
          case .skewY:
            let angle = try Number.parse(context: context, input: &input).get().value
            return .success(SkewYOperator(angle: Double(angle)))
          case .matrix:
            let a = try Number.parse(context: context, input: &input).get().value
            let b = try Number.parse(context: context, input: &input).get().value
            let c = try Number.parse(context: context, input: &input).get().value
            let d = try Number.parse(context: context, input: &input).get().value
            let tx = try Number.parse(context: context, input: &input).get().value
            let ty = try Number.parse(context: context, input: &input).get().value
            return .success(MatrixOperator(a: Double(a), b: Double(b), c: Double(c), d: Double(d), tx: Double(tx), ty: Double(ty)))
          }
        } catch {
          return .failure(error)
        }
      })
    }
    switch result {
    case .success(let ops):
      var transform: CGAffineTransform = .identity
      for op in ops {
        op.apply(transform: &transform)
      }
      return .success(transform)
    case .failure(let error):
      return .failure(error)
    }
  }

  private static func expectComma(input: inout Parser) -> Bool {
    switch input.tryParse({ input in
      input.expectComma()
    }) {
    case .success:
      return true
    case .failure:
      return false
    }
  }
}
