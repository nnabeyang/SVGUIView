import Foundation
import _CSSParser

// The properties of CSS Animations. Each takes a comma-separated list with one value for each animation, from a
// style sheet or the `style` attribute: they aren't presentation attributes.

/// The name of the `@keyframes` rule that an animation runs, or `none`.
enum AnimationName: Sendable, Equatable {
  case none
  case keyframes(String)
}

/// A property of CSS Animations or CSS Transitions, whose value is a list.
protocol AnimationListProperty: StyleProperty where Specified == [Element], Computed == [Element] {
  associatedtype Element: Sendable
  /// One value of the list, or `nil` if it's invalid.
  static func parseOne(_ input: inout _CSSParser.Parser) -> Element?
}

extension AnimationListProperty {
  static var isInherited: Bool { false }

  static func accepts(attributeOn _: SVGElementName) -> Bool {
    false
  }

  static func parse(_ text: String, origin _: DeclarationOrigin) -> [Element]? {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    return parse(css: &input)
  }

  static func parse(css input: inout _CSSParser.Parser) -> [Element]? {
    var values = [Element]()
    repeat {
      guard let value = parseOne(&input) else { return nil }
      values.append(value)
    } while input.tryParse({ $0.expectComma() }).isSuccess
    return input.isExhausted() ? values : nil
  }
}

enum AnimationNameProperty: AnimationListProperty {
  static let id = PropertyID.animationName
  static let initial: [AnimationName] = [.none]
  static let computed = \ComputedStyle.animationName

  static func parseOne(_ input: inout _CSSParser.Parser) -> AnimationName? {
    animationName(&input)
  }
}

enum AnimationDurationProperty: AnimationListProperty {
  static let id = PropertyID.animationDuration
  static let initial: [Double] = [0]
  static let computed = \ComputedStyle.animationDuration

  static func parseOne(_ input: inout _CSSParser.Parser) -> Double? {
    time(&input).flatMap { $0 >= 0 ? $0 : nil }
  }
}

enum AnimationTimingFunctionProperty: AnimationListProperty {
  static let id = PropertyID.animationTimingFunction
  static let initial: [EasingFunction] = [.ease]
  static let computed = \ComputedStyle.animationTimingFunction

  static func parseOne(_ input: inout _CSSParser.Parser) -> EasingFunction? {
    easingFunction(&input)
  }
}

enum AnimationDelayProperty: AnimationListProperty {
  static let id = PropertyID.animationDelay
  static let initial: [Double] = [0]
  static let computed = \ComputedStyle.animationDelay

  static func parseOne(_ input: inout _CSSParser.Parser) -> Double? {
    time(&input)
  }
}

enum AnimationIterationCountProperty: AnimationListProperty {
  static let id = PropertyID.animationIterationCount
  static let initial: [AnimationIterationCount] = [.count(1)]
  static let computed = \ComputedStyle.animationIterationCount

  static func parseOne(_ input: inout _CSSParser.Parser) -> AnimationIterationCount? {
    iterationCount(&input)
  }
}

enum AnimationDirectionProperty: AnimationListProperty {
  static let id = PropertyID.animationDirection
  static let initial: [AnimationDirection] = [.normal]
  static let computed = \ComputedStyle.animationDirection

  static func parseOne(_ input: inout _CSSParser.Parser) -> AnimationDirection? {
    keyword(&input)
  }
}

enum AnimationFillModeProperty: AnimationListProperty {
  static let id = PropertyID.animationFillMode
  static let initial: [AnimationFillMode] = [.none]
  static let computed = \ComputedStyle.animationFillMode

  static func parseOne(_ input: inout _CSSParser.Parser) -> AnimationFillMode? {
    keyword(&input)
  }
}

enum AnimationPlayStateProperty: AnimationListProperty {
  static let id = PropertyID.animationPlayState
  static let initial: [AnimationPlayState] = [.running]
  static let computed = \ComputedStyle.animationPlayState

  static func parseOne(_ input: inout _CSSParser.Parser) -> AnimationPlayState? {
    keyword(&input)
  }
}

/// The shorthand `animation`, which sets every longhand of CSS Animations.
enum AnimationShorthand {
  static let name = "animation"

  /// The declarations of the longhands, or `nil` if the value is invalid.
  static func declarations(css input: inout _CSSParser.Parser) -> [PropertyDeclaration]? {
    let start = input.state
    while case .success = input.next() {}
    switch keyword(removingComments(from: input.slice(from: start.sourcePosition))) {
    case "inherit": return declarations(.inherit)
    case "initial": return declarations(.initial)
    case "unset", "revert", "revert-layer": return declarations(.unset)
    default: input.reset(state: start)
    }
    var animations = [SingleAnimation]()
    repeat {
      guard let animation = SingleAnimation(&input) else { return nil }
      animations.append(animation)
    } while input.tryParse({ $0.expectComma() }).isSuccess
    guard input.isExhausted() else { return nil }
    return [
      PropertyDeclaration(AnimationNameProperty.self, .value(animations.map { $0.name ?? .none })),
      PropertyDeclaration(AnimationDurationProperty.self, .value(animations.map { $0.duration ?? 0 })),
      PropertyDeclaration(AnimationTimingFunctionProperty.self, .value(animations.map { $0.easing ?? .ease })),
      PropertyDeclaration(AnimationDelayProperty.self, .value(animations.map { $0.delay ?? 0 })),
      PropertyDeclaration(
        AnimationIterationCountProperty.self, .value(animations.map { $0.iterationCount ?? .count(1) })),
      PropertyDeclaration(AnimationDirectionProperty.self, .value(animations.map { $0.direction ?? .normal })),
      PropertyDeclaration(AnimationFillModeProperty.self, .value(animations.map { $0.fillMode ?? .none })),
      PropertyDeclaration(AnimationPlayStateProperty.self, .value(animations.map { $0.playState ?? .running })),
    ]
  }

  /// The declarations that give every longhand the same keyword.
  private static func declarations(_ keyword: Declared<Never>) -> [PropertyDeclaration] {
    func declaration<P: StyleProperty>(_: P.Type) -> PropertyDeclaration {
      let value: Declared<P.Specified> =
        switch keyword {
        case .inherit: .inherit
        case .initial: .initial
        case .unset, .value: .unset
        }
      return PropertyDeclaration(P.self, value)
    }
    return [
      declaration(AnimationNameProperty.self), declaration(AnimationDurationProperty.self),
      declaration(AnimationTimingFunctionProperty.self), declaration(AnimationDelayProperty.self),
      declaration(AnimationIterationCountProperty.self), declaration(AnimationDirectionProperty.self),
      declaration(AnimationFillModeProperty.self), declaration(AnimationPlayStateProperty.self),
    ]
  }

  /// The values of one animation in the shorthand, which can come in any order. A value that more than one
  /// longhand takes, such as `none`, goes to the first of them that isn't set yet, in the order of the grammar:
  /// the duration, the easing function, the delay, the iteration count, the direction, the fill mode, the play
  /// state and the name.
  private struct SingleAnimation {
    var duration: Double?
    var easing: EasingFunction?
    var delay: Double?
    var iterationCount: AnimationIterationCount?
    var direction: AnimationDirection?
    var fillMode: AnimationFillMode?
    var playState: AnimationPlayState?
    var name: AnimationName?

    init?(_ input: inout _CSSParser.Parser) {
      var isEmpty = true
      while true {
        let state = input.state
        switch input.next() {
        case .failure, .success(.comma):
          input.reset(state: state)
          if isEmpty { return nil }
          return
        default:
          input.reset(state: state)
        }
        isEmpty = false
        if let time = attempt(&input, time) {
          if duration == nil, time >= 0 {
            duration = time
          } else if delay == nil {
            delay = time
          } else {
            return nil
          }
        } else if easing == nil, let value = attempt(&input, easingFunction) {
          easing = value
        } else if iterationCount == nil, let value = attempt(&input, SVGCore.iterationCount) {
          iterationCount = value
        } else if direction == nil, let value: AnimationDirection = attempt(&input, keyword) {
          direction = value
        } else if fillMode == nil, let value: AnimationFillMode = attempt(&input, keyword) {
          fillMode = value
        } else if playState == nil, let value: AnimationPlayState = attempt(&input, keyword) {
          playState = value
        } else if name == nil, let value = attempt(&input, animationName) {
          name = value
        } else {
          return nil
        }
      }
    }
  }
}

/// The value that `parse` reads from the input, or `nil` with the input as it was if it reads none.
func attempt<T>(_ input: inout _CSSParser.Parser, _ parse: (inout _CSSParser.Parser) -> T?) -> T? {
  let state = input.state
  if let value = parse(&input) { return value }
  input.reset(state: state)
  return nil
}

/// A `<time>`, in seconds.
func time(_ input: inout _CSSParser.Parser) -> Double? {
  guard case .success(.dimention(let dimension)) = input.next() else { return nil }
  switch dimension.unit.lowercased() {
  case "s": return Double(dimension.value)
  case "ms": return Double(dimension.value) / 1000
  default: return nil
  }
}

/// A keyword of the given type, whose raw values are in lowercase.
func keyword<T: RawRepresentable & CaseIterable>(_ input: inout _CSSParser.Parser) -> T?
where T.RawValue == String {
  guard case .success(.ident(let name)) = input.next() else { return nil }
  return T(rawValue: name.lowercased())
}

private func iterationCount(_ input: inout _CSSParser.Parser) -> AnimationIterationCount? {
  switch input.next() {
  case .success(.number(let number)) where number.value >= 0: .count(Double(number.value))
  case .success(.ident(let name)) where name.lowercased() == "infinite": .infinite
  default: nil
  }
}

private func animationName(_ input: inout _CSSParser.Parser) -> AnimationName? {
  let state = input.state
  if case .success(.ident(let name)) = input.next(), name.lowercased() == "none" { return AnimationName.none }
  input.reset(state: state)
  return keyframesName(&input).map { .keyframes($0) }
}

/// The name of a `@keyframes` rule: an identifier that isn't a keyword, or a string. Names are case-sensitive.
func keyframesName(_ input: inout _CSSParser.Parser) -> String? {
  switch input.next() {
  case .success(.ident(let name)):
    let keywords: Set = ["none", "initial", "inherit", "unset", "default", "revert", "revert-layer"]
    return keywords.contains(name.lowercased()) ? nil : name
  case .success(.quotedString(let name)):
    return name
  default:
    return nil
  }
}

/// An `<easing-function>` of CSS Easing Functions.
func easingFunction(_ input: inout _CSSParser.Parser) -> EasingFunction? {
  switch input.next() {
  case .success(.ident(let name)):
    switch name.lowercased() {
    case "linear": return .linear
    case "ease": return .ease
    case "ease-in": return .easeIn
    case "ease-out": return .easeOut
    case "ease-in-out": return .easeInOut
    case "step-start": return .steps(1, .jumpStart)
    case "step-end": return .steps(1, .jumpEnd)
    default: return nil
    }
  case .success(.function(let name)):
    let parse: (inout _CSSParser.Parser) -> EasingFunction? =
      switch name.lowercased() {
      case "cubic-bezier": cubicBezier
      case "steps": steps
      case "linear": linear
      default: { _ in nil }
      }
    let result: Result<EasingFunction, CSSParseError> = input.parseNestedBlock { input in
      guard let value = parse(&input) else { return .failure(input.newCustomError(error: .invalid)) }
      return .success(value)
    }
    return try? result.get()
  default:
    return nil
  }
}

private func cubicBezier(_ input: inout _CSSParser.Parser) -> EasingFunction? {
  var values = [Double]()
  for index in 0..<4 {
    if index > 0, case .failure = input.expectComma() { return nil }
    guard case .success(let value) = input.expectNumber() else { return nil }
    values.append(Double(value))
  }
  guard (0...1).contains(values[0]), (0...1).contains(values[2]) else { return nil }
  return .cubicBezier(x1: values[0], y1: values[1], x2: values[2], y2: values[3])
}

private func steps(_ input: inout _CSSParser.Parser) -> EasingFunction? {
  guard case .success(let count) = input.expectInteger() else { return nil }
  var position = EasingFunction.StepPosition.jumpEnd
  if input.tryParse({ $0.expectComma() }).isSuccess {
    guard case .success(let name) = input.expectIdent() else { return nil }
    switch name.lowercased() {
    case "jump-start", "start": position = .jumpStart
    case "jump-end", "end": position = .jumpEnd
    case "jump-none": position = .jumpNone
    case "jump-both": position = .jumpBoth
    default: return nil
    }
  }
  guard count >= (position == .jumpNone ? 2 : 1) else { return nil }
  return .steps(Int(count), position)
}

/// The stops of `linear()`. Each stop is a number with up to two percentages before or after it, and a stop with
/// two percentages is two points with the same output.
private func linear(_ input: inout _CSSParser.Parser) -> EasingFunction? {
  var stops: [(output: Double, input: Double?)] = []
  repeat {
    var output: Double?
    var inputs = [Double]()
    var inputsBeforeOutput = 0
    loop: while true {
      let state = input.state
      switch input.next() {
      case .success(.number(let number)) where output == nil:
        output = Double(number.value)
        inputsBeforeOutput = inputs.count
      case .success(.percentage(let percentage)) where inputs.count < 2:
        inputs.append(Double(percentage.unitValue))
      default:
        input.reset(state: state)
        break loop
      }
    }
    // The percentages are all before the number or all after it.
    guard let output, inputsBeforeOutput == 0 || inputsBeforeOutput == inputs.count else { return nil }
    if inputs.isEmpty {
      stops.append((output, nil))
    } else {
      stops.append(contentsOf: inputs.map { (output, $0) })
    }
  } while input.tryParse({ $0.expectComma() }).isSuccess
  return EasingFunction.piecewiseLinear(stops: stops)
}

extension Result {
  var isSuccess: Bool {
    if case .success = self { true } else { false }
  }
}
