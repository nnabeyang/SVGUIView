import Foundation
import _CSSParser

// The properties of CSS Transitions. Like the properties of CSS Animations, each takes a comma-separated list with
// one value for each transition, from a style sheet or the `style` attribute.

/// The property that a transition changes.
enum TransitionProperty: Sendable, Equatable {
  /// No property, which only comes alone in a list.
  case none
  case all
  case property(PropertyID)
  /// A name that isn't a property that SVGUIView knows, which keeps the position of the values of the other lists.
  case unrecognized(String)
}

/// Whether transitions change properties whose values can't be interpolated.
enum TransitionBehavior: String, CaseIterable, Sendable {
  case normal
  case allowDiscrete = "allow-discrete"
}

enum TransitionPropertyProperty: AnimationListProperty {
  static let id = PropertyID.transitionProperty
  static let initial: [TransitionProperty] = [.all]
  static let computed = \ComputedStyle.transitionProperty

  static func parseOne(_ input: inout _CSSParser.Parser) -> TransitionProperty? {
    transitionProperty(&input)
  }

  static func parse(css input: inout _CSSParser.Parser) -> [TransitionProperty]? {
    let state = input.state
    if case .success(.ident(let name)) = input.next(), name.lowercased() == "none", input.isExhausted() {
      return [.none]
    }
    input.reset(state: state)
    var values = [TransitionProperty]()
    repeat {
      guard let value = parseOne(&input), value != .none else { return nil }
      values.append(value)
    } while input.tryParse({ $0.expectComma() }).isSuccess
    return input.isExhausted() ? values : nil
  }
}

enum TransitionDurationProperty: AnimationListProperty {
  static let id = PropertyID.transitionDuration
  static let initial: [Double] = [0]
  static let computed = \ComputedStyle.transitionDuration

  static func parseOne(_ input: inout _CSSParser.Parser) -> Double? {
    time(&input).flatMap { $0 >= 0 ? $0 : nil }
  }
}

enum TransitionTimingFunctionProperty: AnimationListProperty {
  static let id = PropertyID.transitionTimingFunction
  static let initial: [EasingFunction] = [.ease]
  static let computed = \ComputedStyle.transitionTimingFunction

  static func parseOne(_ input: inout _CSSParser.Parser) -> EasingFunction? {
    easingFunction(&input)
  }
}

enum TransitionDelayProperty: AnimationListProperty {
  static let id = PropertyID.transitionDelay
  static let initial: [Double] = [0]
  static let computed = \ComputedStyle.transitionDelay

  static func parseOne(_ input: inout _CSSParser.Parser) -> Double? {
    time(&input)
  }
}

enum TransitionBehaviorProperty: AnimationListProperty {
  static let id = PropertyID.transitionBehavior
  static let initial: [TransitionBehavior] = [.normal]
  static let computed = \ComputedStyle.transitionBehavior

  static func parseOne(_ input: inout _CSSParser.Parser) -> TransitionBehavior? {
    keyword(&input)
  }
}

/// `none`, `all` or the name of a property, which is ASCII case-insensitive. The keywords that every property takes
/// aren't names.
private func transitionProperty(_ input: inout _CSSParser.Parser) -> TransitionProperty? {
  guard case .success(.ident(let ident)) = input.next() else { return nil }
  let name = ident.lowercased()
  switch name {
  case "none": return TransitionProperty.none
  case "all": return .all
  case "initial", "inherit", "unset", "default", "revert", "revert-layer": return nil
  default: return PropertyID(rawValue: name).map { .property($0) } ?? .unrecognized(name)
  }
}

extension PropertyID {
  /// Whether the property is one of CSS Transitions.
  var isTransition: Bool {
    switch self {
    case .transitionProperty, .transitionDuration, .transitionTimingFunction, .transitionDelay, .transitionBehavior:
      true
    default:
      false
    }
  }

  /// Whether animations change the property, which the properties of CSS Animations and CSS Transitions don't.
  var isAnimatable: Bool {
    !isAnimation && !isTransition
  }
}
