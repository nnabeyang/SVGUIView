import CoreGraphics
import Foundation

/// A filter function of the CSS that adjusts the colors by an amount.
enum SVGColorAdjust: String, CaseIterable {
  case brightness
  case contrast
  case grayscale
  case invert
  case opacity
  case saturate
  case sepia

  /// Whether amounts above 1 have the effect of 1.
  var isClamped: Bool {
    switch self {
    case .grayscale, .invert, .opacity, .sepia: true
    case .brightness, .contrast, .saturate: false
    }
  }
}

/// An item of the value of `filter`: a reference to a `<filter>` element, or a filter function of the CSS.
enum SVGFilterFunction: Equatable {
  case url(String)
  /// A blur by a standard deviation.
  case blur(SVGLength)
  /// A shadow of a color, at an offset, blurred by a standard deviation.
  case dropShadow(color: ColorValue, dx: SVGLength, dy: SVGLength, deviation: SVGLength)
  /// An adjustment of the colors by an amount, where 0 changes nothing for most of them and 1 for the others.
  case colorAdjust(SVGColorAdjust, Double)
  /// A rotation of the hues by an angle in degrees.
  case hueRotate(Double)
}

/// The value of `filter`: none, or the filters that apply one after another.
enum SVGFilter: Equatable {
  case none
  case list([SVGFilterFunction])

  /// The value of a text, or `nil` if any of its items isn't valid, which makes the whole value invalid.
  init?(description: String) {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.lowercased() == "none" {
      self = .none
      return
    }
    var functions = [SVGFilterFunction]()
    var rest = Substring(text)
    while true {
      rest = rest.drop(while: \.isWhitespace)
      guard !rest.isEmpty else { break }
      guard let open = rest.firstIndex(of: "(") else { return nil }
      let name = rest[..<open].lowercased()
      // The arguments end at the parenthesis that closes the one that opens them, as colors have parentheses too.
      var depth = 0
      var close: Substring.Index?
      for index in rest[open...].indices {
        if rest[index] == "(" {
          depth += 1
        } else if rest[index] == ")" {
          depth -= 1
          if depth == 0 {
            close = index
            break
          }
        }
      }
      guard let close, let function = Self.function(name, arguments: rest[rest.index(after: open)..<close]) else {
        return nil
      }
      functions.append(function)
      rest = rest[rest.index(after: close)...]
      // An item ends at whitespace or at the end of the value.
      guard rest.isEmpty || rest.first!.isWhitespace else { return nil }
    }
    guard !functions.isEmpty else { return nil }
    self = .list(functions)
  }

  /// The IDs of the `<filter>` elements that the value references.
  var references: [String] {
    guard case .list(let functions) = self else { return [] }
    return functions.compactMap {
      if case .url(let id) = $0 { id } else { nil }
    }
  }

  private static func function(_ name: String, arguments text: Substring) -> SVGFilterFunction? {
    let arguments = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch name {
    case "url":
      var reference = Substring(arguments)
      if let quote = reference.first, quote == "\"" || quote == "'" {
        guard reference.count >= 2, reference.last == quote else { return nil }
        reference = reference.dropFirst().dropLast()
      }
      guard reference.first == "#", reference.count > 1 else { return nil }
      return .url(String(reference.dropFirst()))
    case "blur":
      guard !arguments.isEmpty else { return .blur(.number(0)) }
      guard let deviation = length(arguments), !isNegative(arguments) else { return nil }
      return .blur(deviation)
    case "drop-shadow":
      return dropShadow(arguments)
    case "hue-rotate":
      guard !arguments.isEmpty else { return .hueRotate(0) }
      return angle(arguments).map { .hueRotate($0) }
    default:
      guard let adjust = SVGColorAdjust(rawValue: name) else { return nil }
      guard !arguments.isEmpty else { return .colorAdjust(adjust, 1) }
      guard let amount = amount(arguments), amount >= 0 else { return nil }
      return .colorAdjust(adjust, adjust.isClamped ? min(amount, 1) : amount)
    }
  }

  /// The arguments of `drop-shadow()`: a color before or after two or three lengths, which are the offset and the
  /// standard deviation. The color is `currentColor` where it's missing.
  private static func dropShadow(_ text: String) -> SVGFilterFunction? {
    var tokens = [String]()
    var token = ""
    var depth = 0
    for character in text {
      switch character {
      case "(":
        depth += 1
        token.append(character)
      case ")":
        depth -= 1
        token.append(character)
      case "," where depth == 0:
        // The arguments are separated by whitespace only.
        return nil
      case _ where character.isWhitespace && depth == 0:
        if !token.isEmpty {
          tokens.append(token)
          token = ""
        }
      default:
        token.append(character)
      }
    }
    if !token.isEmpty {
      tokens.append(token)
    }
    // The color is the first or the last argument, and the others are lengths.
    var color: ColorValue?
    if let first = tokens.first, length(first) == nil {
      guard let value = ColorValue(first) else { return nil }
      color = value
      tokens.removeFirst()
    } else if let last = tokens.last, length(last) == nil {
      guard let value = ColorValue(last) else { return nil }
      color = value
      tokens.removeLast()
    }
    let lengths = tokens.compactMap(length)
    guard lengths.count == tokens.count, (2...3).contains(lengths.count) else { return nil }
    if lengths.count == 3, isNegative(tokens[2]) { return nil }
    return .dropShadow(
      color: color ?? .currentColor, dx: lengths[0], dy: lengths[1], deviation: lengths.count == 3 ? lengths[2] : .number(0))
  }

  /// A length, which can be a number without a unit as in the other attributes of SVG, and not a percentage.
  private static func length(_ text: String) -> SVGLength? {
    guard let length = SVGLength(text) else { return nil }
    if case .percent = length { return nil }
    return length
  }

  /// Whether the number of a length is less than 0.
  private static func isNegative(_ text: String) -> Bool {
    Double(text.prefix { "+-.0123456789eE".contains($0) }).map { $0 < 0 } ?? false
  }

  /// An amount, a number or a percentage.
  private static func amount(_ text: String) -> Double? {
    if text.hasSuffix("%") {
      return Double(text.dropLast()).map { $0 / 100 }
    }
    return Double(text)
  }

  /// An angle in degrees, of a number in degrees or with the unit `deg`, `grad`, `rad` or `turn`.
  private static func angle(_ text: String) -> Double? {
    let units: [(String, Double)] = [("deg", 1), ("grad", 0.9), ("rad", 180 / .pi), ("turn", 360)]
    let lowercased = text.lowercased()
    for (unit, degrees) in units where lowercased.hasSuffix(unit) {
      return Double(lowercased.dropLast(unit.count)).map { $0 * degrees }
    }
    return Double(text)
  }
}
