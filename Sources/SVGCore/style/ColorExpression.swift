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
  /// A color with missing components, which are `none` in its function, and which interpolation takes from the other
  /// color, as CSS Color 4 specifies. Elsewhere they're 0.
  case missing(MissingColor)

  /// Whether `currentcolor` is part of the expression.
  var containsCurrentColor: Bool {
    switch self {
    case .color, .missing: false
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
    case .missing(let color):
      return color.color
    case .mix(let space, let method, let color1, let percentage1, let color2, let percentage2):
      let black = SVGColor.named(SVGColorName(name: "black"))
      // The percentages are checked when the expression is read, so the mix is a color.
      guard
        let mixed = ColorConversion.mix(
          color1.components(in: space, currentColor: currentColor), percentage1,
          color2.components(in: space, currentColor: currentColor), percentage2, in: space, hue: method)
      else { return black }
      return SVGAttributeScanner.color(red: mixed.rgb.0, green: mixed.rgb.1, blue: mixed.rgb.2, alpha: mixed.alpha)
    case .relative(let relative):
      return relative.color(origin: relative.origin.resolved(currentColor: currentColor))
        ?? .named(SVGColorName(name: "black"))
    }
  }

  /// The color with its missing components, or `nil` for a color without any.
  func missingColor(currentColor: SVGColor) -> MissingColor? {
    switch self {
    case .missing(let color): color
    case .relative(let relative): relative.missingColor(origin: relative.origin.resolved(currentColor: currentColor))
    default: nil
    }
  }

  /// The components of the color in a space that `color-mix()` interpolates in, with `nil` for the components that
  /// are missing, and for the hue of a color without one, and its alpha, `nil` if it's missing.
  func components(in space: ColorMixSpace, currentColor: SVGColor) -> (components: [Double?], alpha: Double?) {
    if let missing = missingColor(currentColor: currentColor) { return missing.components(in: space) }
    let black = SVGColor.named(SVGColorName(name: "black"))
    let c = resolved(currentColor: currentColor).components ?? black.components!
    return (space.components(ofSRGB: (c.red, c.green, c.blue)), c.alpha)
  }

  /// The expression, or the color that it is when `currentcolor` isn't part of it. A color with missing components
  /// keeps them.
  var simplified: ColorExpression {
    if containsCurrentColor { return self }
    let black = SVGColor.named(SVGColorName(name: "black"))
    if let missing = missingColor(currentColor: black) { return .missing(missing) }
    return .color(resolved(currentColor: black))
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

  /// The color with the components of an origin and the components that are `none` missing, or `nil` for a color
  /// without missing components or with components that the function doesn't take.
  func missingColor(origin: SVGColor) -> MissingColor? {
    let isMissing = components.map { $0 == .none }
    let isAlphaMissing = alpha == SVGAttributeScanner.ColorComponent.none
    guard isMissing.contains(true) || isAlphaMissing, let color = color(origin: origin) else { return nil }
    return MissingColor(function: function, isMissing: isMissing, isAlphaMissing: isAlphaMissing, color: color)
  }

  /// The color with the components of an origin, or `nil` for components that the function doesn't take.
  func color(origin: SVGColor) -> SVGColor? {
    guard let c = origin.components else { return nil }
    var channels = function.channels(ofSRGB: (c.red, c.green, c.blue))
    channels["alpha"] = c.alpha
    func value(_ component: SVGAttributeScanner.ColorComponent) -> SVGAttributeScanner.ColorComponent {
      switch component {
      case .channel(let name):
        return .number(channels[name] ?? 0)
      case .calc(let expression, let isPercentage):
        let value = expression.node.value(length: { _ in 0 }, percentage: { $0 }, channel: { channels[$0] ?? 0 })
        return isPercentage ? .percentage(value) : .number(value)
      default:
        return component
      }
    }
    return SVGAttributeScanner.color(
      of: function, components: components.map(value), alpha: value(alpha ?? .channel("alpha")), isLegacy: false,
      isRelative: true)
  }
}

/// A color whose function has missing components, which are `none`, with the color that it is where they're 0.
struct MissingColor: Sendable, Equatable {
  let function: ColorFunction
  /// Whether each of the three components of the function is missing.
  let isMissing: [Bool]
  let isAlphaMissing: Bool
  /// The color with the missing components as 0.
  let color: SVGColor

  /// The components of the color in a space that `color-mix()` interpolates in, with `nil` for the components that
  /// are missing, which are the components of the space analogous to the missing ones of the function, as CSS Color
  /// 4 carries them forward, and for the hue of a color without one, and its alpha, `nil` if it's missing.
  func components(in space: ColorMixSpace) -> (components: [Double?], alpha: Double?) {
    let black = SVGColor.named(SVGColorName(name: "black"))
    let c = color.components ?? black.components!
    var components = space.components(ofSRGB: (c.red, c.green, c.blue))
    let missingKinds = Set(zip(function.componentKinds, isMissing).compactMap { $1 ? $0 : nil })
    for (index, kind) in space.componentKinds.enumerated() where kind.map(missingKinds.contains) == true {
      components[index] = nil
    }
    return (components, isAlphaMissing ? nil : c.alpha)
  }

  /// The color with its missing components as the ones of another color in sRGB, which colors are interpolated in,
  /// for the missing components of the function that are analogous to the components of sRGB.
  func filled(from other: SVGColor) -> SVGColor {
    let (components, alpha) = components(in: .sRGB)
    guard let o = other.components else { return color }
    let rgb = [o.red, o.green, o.blue]
    let filled = components.enumerated().map { $1 ?? rgb[$0] }
    return SVGAttributeScanner.color(red: filled[0], green: filled[1], blue: filled[2], alpha: alpha ?? o.alpha)
  }
}

/// A kind of components of color functions and spaces, which CSS Color 4 calls analogous, and carries a missing
/// component forward in when it converts a color to another space.
enum ColorComponentKind: Sendable {
  /// The reds, `r` and `x`.
  case red
  /// The greens, `g` and `y`.
  case green
  /// The blues, `b` and `z`.
  case blue
  case lightness
  /// The chroma and the saturation.
  case colorfulness
  case hue
  /// The opposing `a` of Lab and Oklab.
  case opponentA
  /// The opposing `b` of Lab and Oklab.
  case opponentB
}

extension ColorFunction {
  /// The kinds of the components of the function, or `nil` for a component of no kind, such as the whiteness of
  /// `hwb()`.
  var componentKinds: [ColorComponentKind?] {
    switch self {
    case .rgb, .color: [.red, .green, .blue]
    case .hsl: [.hue, .colorfulness, .lightness]
    case .hwb: [.hue, nil, nil]
    case .lab, .oklab: [.lightness, .opponentA, .opponentB]
    case .lch, .oklch: [.lightness, .colorfulness, .hue]
    }
  }
}

extension ColorMixSpace {
  /// The kinds of the components of the space, or `nil` for a component of no kind, such as the whiteness of HWB.
  var componentKinds: [ColorComponentKind?] {
    switch self {
    case .hsl: [.hue, .colorfulness, .lightness]
    case .hwb: [.hue, nil, nil]
    case .lab, .oklab: [.lightness, .opponentA, .opponentB]
    case .lch, .oklch: [.lightness, .colorfulness, .hue]
    default: [.red, .green, .blue]
    }
  }
}
