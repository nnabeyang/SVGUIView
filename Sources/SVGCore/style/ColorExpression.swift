import Foundation

/// A color that `currentcolor` is part of, such as a `color-mix()` of it, which stays an expression in computed values
/// and is resolved where it's used, with the color of the element, as `currentcolor` is.
///
/// A color without `currentcolor` is mixed when it's read, and is a color, not an expression.
indirect enum ColorExpression: Sendable, Equatable {
  case color(SVGColor)
  case currentColor
  /// `color-mix()` in a space, with the percentages of its colors, `nil` where they're omitted.
  case mix(ColorMixSpace, HueInterpolationMethod, ColorExpression, Double?, ColorExpression, Double?)

  /// Whether `currentcolor` is part of the expression.
  var containsCurrentColor: Bool {
    switch self {
    case .color: false
    case .currentColor: true
    case .mix(_, _, let color1, _, let color2, _): color1.containsCurrentColor || color2.containsCurrentColor
    }
  }

  /// The color, where `currentcolor` is the given color.
  func resolved(currentColor: SVGColor) -> SVGColor {
    switch self {
    case .color(let color):
      return color
    case .currentColor:
      return currentColor
    case .mix(let space, let method, let color1, let percentage1, let color2, let percentage2):
      let black = SVGColor.named(SVGColorName(name: "black"))
      func components(_ color: SVGColor) -> (rgb: ColorConversion.Vector, alpha: Double) {
        let c = color.components ?? black.components!
        return ((c.red, c.green, c.blue), c.alpha)
      }
      // The percentages are checked when the expression is read, so the mix is a color.
      guard
        let mixed = ColorConversion.mix(
          components(color1.resolved(currentColor: currentColor)), percentage1,
          components(color2.resolved(currentColor: currentColor)), percentage2, in: space, hue: method)
      else { return black }
      return SVGAttributeScanner.color(red: mixed.rgb.0, green: mixed.rgb.1, blue: mixed.rgb.2, alpha: mixed.alpha)
    }
  }

  /// The expression, or the color that it is when `currentcolor` isn't part of it.
  var simplified: ColorExpression {
    containsCurrentColor ? self : .color(resolved(currentColor: .named(SVGColorName(name: "black"))))
  }
}
