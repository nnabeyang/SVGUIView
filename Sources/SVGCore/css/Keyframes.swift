import _CSSParser

/// A `@keyframes` rule: the keyframes of the animations that name it.
struct KeyframesRule: Sendable {
  let name: String
  /// The keyframes in the order of the rule.
  let keyframes: [Keyframe]
}

/// A keyframe of a `@keyframes` rule.
struct Keyframe: Sendable {
  /// The offsets that the keyframe applies to, between 0 and 1.
  let offsets: [Double]
  /// The values of the keyframe. Important declarations and the properties of CSS Animations and CSS Transitions are
  /// left out, since keyframes ignore them.
  let declarations: CascadedValues
  /// The easing function from the keyframe to the next one, from its `animation-timing-function`, or `nil` to use
  /// the animation's.
  let easing: EasingFunction?

  init(offsets: [Double], declarations: [CSSDeclaration]) {
    self.offsets = offsets
    let declarations = declarations.filter { $0.importance == .normal }.map(\.declaration)
    self.declarations = CascadedValues(declarations.filter { $0.id.isAnimatable })
    let easings = CascadedValues(declarations).declared(AnimationTimingFunctionProperty.self)
    easing = easings?.count == 1 ? easings?.first : nil
  }
}

/// Parses the keyframes in the block of a `@keyframes` rule.
struct KeyframeListParser: RuleBodyItemParser {
  typealias Declaration = Keyframe
  typealias Prelude = [Double]
  typealias QualifiedRule = Keyframe
  typealias AtRule = Keyframe
  typealias Error = StyleParseErrorKind

  func parseDeclarations() -> Bool {
    true
  }

  func parseQualified() -> Bool {
    true
  }

  /// The offsets of a keyframe: a list of `from`, `to` and percentages from 0% to 100%.
  mutating func parseQualifiedPrelude(input: inout _CSSParser.Parser) -> Result<[Double], CSSParseError> {
    input.parseCommaSeparated { input in
      let start = input.currentSourceLocation
      switch input.next() {
      case .success(.ident(let name)) where name.lowercased() == "from":
        return .success(0)
      case .success(.ident(let name)) where name.lowercased() == "to":
        return .success(1)
      case .success(.percentage(let percentage)) where (0...1).contains(percentage.unitValue):
        return .success(Double(percentage.unitValue))
      case .success(let token):
        return .failure(start.newUnexpectedTokenError(token: token))
      case .failure(let error):
        return .failure(error.into())
      }
    }
  }

  mutating func parseQualifiedBlock(
    prelude: [Double], start _: ParserState, input: inout _CSSParser.Parser
  ) -> Result<Keyframe, CSSParseError> {
    .success(Keyframe(offsets: prelude, declarations: CSSDeclarationParser.declarations(in: &input)))
  }
}

extension PropertyID {
  /// Whether the property is one of CSS Animations.
  var isAnimation: Bool {
    switch self {
    case .animationName, .animationDuration, .animationTimingFunction, .animationDelay, .animationIterationCount,
      .animationDirection, .animationFillMode, .animationPlayState:
      true
    default:
      false
    }
  }
}
