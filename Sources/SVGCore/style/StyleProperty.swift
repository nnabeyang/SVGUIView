import Foundation
import _CSSParser

/// A value of a property as a declaration gives it: a value, or one of the keywords that every property takes.
enum Declared<Value: Sendable>: Sendable {
  case value(Value)
  /// The value of the parent element.
  case inherit
  /// The initial value of the property.
  case initial
  /// `inherit` for a property that's inherited, and `initial` for one that isn't.
  case unset
}

/// Where a declaration comes from, which decides the keywords that it takes.
enum DeclarationOrigin {
  /// A presentation attribute, which takes `inherit` but no other keyword that every property takes.
  case attribute
  /// A style sheet or the `style` attribute.
  case css
}

/// A property that styles set, described once: how it's parsed, its initial value, whether it's inherited, and
/// how its computed value is found.
protocol StyleProperty {
  /// The value that a declaration gives.
  associatedtype Specified: Sendable
  /// The value that drawing reads, with relative values resolved as far as they can be without layout.
  associatedtype Computed: Sendable

  static var id: PropertyID { get }
  static var isInherited: Bool { get }
  static var initial: Computed { get }
  static var computed: WritableKeyPath<ComputedStyle, Computed> & Sendable { get }

  /// Whether elements of the given name take the property as a presentation attribute.
  static func accepts(attributeOn name: SVGElementName) -> Bool
  /// The value of a presentation attribute, or of a declaration with its comments removed, or `nil` if it's
  /// invalid.
  static func parse(_ text: String, origin: DeclarationOrigin) -> Specified?
  /// The value of a declaration in a style sheet, read from its tokens.
  static func parse(css input: inout _CSSParser.Parser) -> Specified?
  static func compute(_ value: Specified, in resolver: StyleResolver) -> Computed
  /// Whether values between two computed values exist, so that SMIL animations interpolate them instead of changing
  /// them discretely.
  static var isInterpolable: Bool { get }
  /// The value between two computed values of an animation, at a progress that can be outside 0 to 1.
  static func interpolated(_ from: Computed, _ to: Computed, progress: Double, in resolver: StyleResolver) -> Computed
  /// The sum of a computed value and the value under it, which additive and accumulating animations use, or `nil`
  /// if the values can't be added.
  static func added(_ value: Computed, to underlying: Computed, in resolver: StyleResolver) -> Computed?
  /// The distance between two computed values, which paced animations use, or `nil` if it isn't defined.
  static func distance(_ from: Computed, _ to: Computed, in resolver: StyleResolver) -> Double?
}

/// Something done with the type of a property, which ``PropertyID/visit(_:)`` calls with the type that describes
/// the property.
protocol StylePropertyVisitor {
  associatedtype Result
  mutating func visit<P: StyleProperty>(_: P.Type) -> Result
}

extension StyleProperty {
  static func accepts(attributeOn _: SVGElementName) -> Bool {
    true
  }

  static func parse(css input: inout _CSSParser.Parser) -> Specified? {
    let start = input.position
    while case .success = input.next() {}
    return parse(removingComments(from: input.slice(from: start)), origin: .css)
  }
}

extension StyleProperty where Specified == Computed {
  static func compute(_ value: Specified, in _: StyleResolver) -> Computed {
    value
  }
}

extension StyleProperty {
  static var isInterpolable: Bool { false }

  /// One of the values, for a property whose values can't be interpolated.
  static func interpolated(_ from: Computed, _ to: Computed, progress: Double, in _: StyleResolver) -> Computed {
    discrete(from, to, progress: progress)
  }

  /// No sum, for a property whose values can't be added.
  static func added(_: Computed, to _: Computed, in _: StyleResolver) -> Computed? {
    nil
  }

  /// No distance, for a property whose values have none.
  static func distance(_: Computed, _: Computed, in _: StyleResolver) -> Double? {
    nil
  }
}

extension StyleProperty where Computed: Animatable {
  static var isInterpolable: Bool { true }

  static func interpolated(_ from: Computed, _ to: Computed, progress: Double, in _: StyleResolver) -> Computed {
    from.animated(to: to, progress: progress)
  }

  static func added(_ value: Computed, to underlying: Computed, in _: StyleResolver) -> Computed? {
    underlying.adding(value)
  }

  static func distance(_ from: Computed, _ to: Computed, in _: StyleResolver) -> Double? {
    from.pacedDistance(to: to)
  }
}

extension StyleProperty {
  /// The declared value of a presentation attribute, or `nil` if the attribute is invalid.
  static func declared(attribute text: String) -> Declared<Specified>? {
    if keyword(text) == "inherit" { return .inherit }
    return parse(text, origin: .attribute).map { .value($0) }
  }

  /// The declared value of a declaration in a style sheet, or `nil` if the declaration is invalid.
  static func declared(css input: inout _CSSParser.Parser) -> Declared<Specified>? {
    let start = input.state
    while case .success = input.next() {}
    switch keyword(removingComments(from: input.slice(from: start.sourcePosition))) {
    case "inherit":
      return .inherit
    case "initial":
      return .initial
    case "unset", "revert", "revert-layer":
      return .unset
    default:
      input.reset(state: start)
      return parse(css: &input).map { .value($0) }
    }
  }
}

/// The text of a value without whitespace around it, in lowercase, to compare with keywords.
func keyword(_ text: String) -> String {
  text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// The text of a declaration's value, with its comments replaced by spaces.
func removingComments(from text: String) -> String {
  guard text.contains("/*") else { return text }
  var result = ""
  var rest = text[...]
  while let start = rest.range(of: "/*") {
    result += rest[..<start.lowerBound]
    result += " "
    guard let end = rest[start.upperBound...].range(of: "*/") else { return result }
    rest = rest[end.upperBound...]
  }
  return result + rest
}

/// What the computed value of a property depends on: the element's other computed values, which are computed in the
/// order of ``PropertyID``, and the computed values of its parent and of the root element.
struct StyleResolver {
  /// The computed values of the element so far. The values of the properties that come before the one being
  /// computed in ``PropertyID`` are final.
  var style: ComputedStyle
  let parent: ComputedStyle
  let root: ComputedStyle

  /// The computed value of a declared value of the property, or of no declaration.
  func computed<P: StyleProperty>(_ declared: Declared<P.Specified>?, of _: P.Type) -> P.Computed {
    switch declared {
    case .value(let value): P.compute(value, in: self)
    case .inherit: parent[keyPath: P.computed]
    case .initial: P.initial
    case .unset, nil: P.isInherited ? parent[keyPath: P.computed] : P.initial
    }
  }
}
