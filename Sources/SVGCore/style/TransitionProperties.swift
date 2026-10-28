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

/// The shorthand `transition`, which sets every longhand of CSS Transitions.
enum TransitionShorthand {
  static let name = "transition"

  /// The longhands, in the order of their declarations.
  static var longhands: [any StyleProperty.Type] {
    [
      TransitionPropertyProperty.self, TransitionDurationProperty.self, TransitionTimingFunctionProperty.self,
      TransitionDelayProperty.self, TransitionBehaviorProperty.self,
    ]
  }

  /// The declarations of the longhands, or `nil` if the value is invalid.
  static func declarations(css input: inout _CSSParser.Parser) -> [PropertyDeclaration]? {
    if let keyword = wideKeyword(&input) {
      return keywordDeclarations(keyword, of: longhands)
    }
    var transitions = [SingleTransition]()
    repeat {
      guard let transition = SingleTransition(&input) else { return nil }
      transitions.append(transition)
    } while input.tryParse({ $0.expectComma() }).isSuccess
    guard input.isExhausted() else { return nil }
    // `none` only comes in a shorthand with one transition.
    if transitions.count > 1, transitions.contains(where: { $0.property == TransitionProperty.none }) { return nil }
    return [
      PropertyDeclaration(TransitionPropertyProperty.self, .value(transitions.map { $0.property ?? .all })),
      PropertyDeclaration(TransitionDurationProperty.self, .value(transitions.map { $0.duration ?? 0 })),
      PropertyDeclaration(TransitionTimingFunctionProperty.self, .value(transitions.map { $0.easing ?? .ease })),
      PropertyDeclaration(TransitionDelayProperty.self, .value(transitions.map { $0.delay ?? 0 })),
      PropertyDeclaration(TransitionBehaviorProperty.self, .value(transitions.map { $0.behavior ?? .normal })),
    ]
  }

  /// The values of one transition in the shorthand, which can come in any order. The first time that isn't negative
  /// is the duration, and the other time is the delay. An identifier is the easing function or the behavior when
  /// that isn't set yet, and the property otherwise, as the name of an animation is in `animation`.
  private struct SingleTransition {
    var property: TransitionProperty?
    var duration: Double?
    var easing: EasingFunction?
    var delay: Double?
    var behavior: TransitionBehavior?

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
        } else if behavior == nil, let value: TransitionBehavior = attempt(&input, keyword) {
          behavior = value
        } else if property == nil, let value = attempt(&input, transitionProperty) {
          property = value
        } else {
          return nil
        }
      }
    }
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
