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
  /// A relative color, such as `rgb(from currentcolor r g 0)`.
  case relative(RelativeColor)

  /// Whether `currentcolor` is part of the expression.
  var containsCurrentColor: Bool {
    switch self {
    case .color: false
    case .currentColor: true
    case .mix(_, _, let color1, _, let color2, _): color1.containsCurrentColor || color2.containsCurrentColor
    case .relative(let relative): relative.origin.containsCurrentColor
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
    case .relative(let relative):
      return relative.color(origin: relative.origin.resolved(currentColor: currentColor))
        ?? .named(SVGColorName(name: "black"))
    }
  }

  /// The expression, or the color that it is when `currentcolor` isn't part of it.
  var simplified: ColorExpression {
    containsCurrentColor ? self : .color(resolved(currentColor: .named(SVGColorName(name: "black"))))
  }
}

/// A color function that a relative color can be written in.
enum ColorFunction: Sendable, Equatable {
  case rgb
  case hsl
  case hwb
  case lab
  case lch
  case oklab
  case oklch
  /// `color()` in a color space.
  case color(CSSColorSpace)

  /// The function of a name, or `nil` for one that isn't a color function. `color()` is in sRGB until its space is
  /// read.
  init?(_ type: SVGFillType) {
    switch type {
    case .rgb, .rgba: self = .rgb
    case .hsl, .hsla: self = .hsl
    case .hwb: self = .hwb
    case .lab: self = .lab
    case .lch: self = .lch
    case .oklab: self = .oklab
    case .oklch: self = .oklch
    case .color: self = .color(.sRGB)
    case .colorMix, .url, .inherit, .current: return nil
    }
  }

  /// The index of the hue among the components, or `nil` for a function without one.
  var hueIndex: Int? {
    switch self {
    case .hsl, .hwb: 0
    case .lch, .oklch: 2
    default: nil
    }
  }

  /// The names of the components of the function, which a relative color in it takes from its origin, in order.
  var channelNames: Set<String> {
    Set(orderedChannelNames)
  }

  private var orderedChannelNames: [String] {
    switch self {
    case .rgb: ["r", "g", "b"]
    case .hsl: ["h", "s", "l"]
    case .hwb: ["h", "w", "b"]
    case .lab, .oklab: ["l", "a", "b"]
    case .lch, .oklch: ["l", "c", "h"]
    case .color(let space):
      switch space {
      case .xyz, .xyzD50, .xyzD65: ["x", "y", "z"]
      default: ["r", "g", "b"]
      }
    }
  }

  /// The values of the components of a color of sRGB in the function, by their names, as numbers that the function
  /// takes: 0 to 255 for `rgb()`, 0 to 100 for the saturation, the lightness, the whiteness and the blackness of
  /// `hsl()` and `hwb()`, and the hue in degrees, which is 0 for a color without one.
  func channels(ofSRGB rgb: ColorConversion.Vector) -> [String: Double] {
    let values: [Double]
    switch self {
    case .rgb: values = [rgb.0 * 255, rgb.1 * 255, rgb.2 * 255]
    case .hsl: values = ColorMixSpace.hsl.components(ofSRGB: rgb).map { $0 ?? 0 }
    case .hwb: values = ColorMixSpace.hwb.components(ofSRGB: rgb).map { $0 ?? 0 }
    case .lab: values = ColorMixSpace.lab.components(ofSRGB: rgb).map { $0 ?? 0 }
    case .lch: values = ColorMixSpace.lch.components(ofSRGB: rgb).map { $0 ?? 0 }
    case .oklab: values = ColorMixSpace.oklab.components(ofSRGB: rgb).map { $0 ?? 0 }
    case .oklch: values = ColorMixSpace.oklch.components(ofSRGB: rgb).map { $0 ?? 0 }
    case .color(let space):
      let c = ColorConversion.components(ofSRGB: rgb, in: space)
      values = [c.0, c.1, c.2]
    }
    return Dictionary(uniqueKeysWithValues: zip(orderedChannelNames, values))
  }
}

/// A relative color: a color function whose components can be the components of its origin, by their names.
struct RelativeColor: Sendable, Equatable {
  let function: ColorFunction
  let origin: ColorExpression
  let components: [SVGAttributeScanner.ColorComponent]
  /// The alpha, which is the alpha of the origin where it's omitted.
  let alpha: SVGAttributeScanner.ColorComponent?

  /// The color with the components of an origin, or `nil` for components that the function doesn't take.
  func color(origin: SVGColor) -> SVGColor? {
    guard let c = origin.components else { return nil }
    var channels = function.channels(ofSRGB: (c.red, c.green, c.blue))
    channels["alpha"] = c.alpha
    func value(_ component: SVGAttributeScanner.ColorComponent) -> SVGAttributeScanner.ColorComponent {
      guard case .channel(let name) = component else { return component }
      return .number(channels[name] ?? 0)
    }
    return SVGAttributeScanner.color(
      of: function, components: components.map(value), alpha: value(alpha ?? .channel("alpha")), isLegacy: false,
      isRelative: true)
  }
}
