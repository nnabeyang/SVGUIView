import Foundation

/// A color space that `color-mix()` interpolates in, from CSS Color 4.
enum ColorMixSpace: String, Sendable {
  case sRGB = "srgb"
  case sRGBLinear = "srgb-linear"
  case displayP3 = "display-p3"
  case a98RGB = "a98-rgb"
  case proPhotoRGB = "prophoto-rgb"
  case rec2020
  case lab
  case oklab
  case xyz
  case xyzD50 = "xyz-d50"
  case xyzD65 = "xyz-d65"
  case hsl
  case hwb
  case lch
  case oklch

  /// Whether the space has a hue, which `color-mix()` interpolates around the circle of hues.
  var isPolar: Bool {
    switch self {
    case .hsl, .hwb, .lch, .oklch: true
    default: false
    }
  }

  /// The index of the hue among the components, or `nil` for a space without one.
  var hueIndex: Int? {
    switch self {
    case .hsl, .hwb: 0
    case .lch, .oklch: 2
    default: nil
    }
  }

  /// The components of a color of sRGB in the space, where the hue is `nil` for a color without one, such as a gray.
  func components(ofSRGB rgb: ColorConversion.Vector) -> [Double?] {
    switch self {
    case .sRGB: return [rgb.0, rgb.1, rgb.2]
    case .lab:
      let lab = ColorConversion.lab(ofSRGB: rgb)
      return [lab.0, lab.1, lab.2]
    case .oklab:
      let lab = ColorConversion.oklab(ofSRGB: rgb)
      return [lab.0, lab.1, lab.2]
    case .hsl:
      let hsl = ColorConversion.hsl(ofSRGB: rgb)
      return [hsl.hue, hsl.saturation, hsl.lightness]
    case .hwb:
      let hue = ColorConversion.hsl(ofSRGB: rgb).hue
      let whiteness = min(rgb.0, rgb.1, rgb.2) * 100
      let blackness = (1 - max(rgb.0, rgb.1, rgb.2)) * 100
      // A gray has no hue.
      return [whiteness + blackness >= 100 - 1e-7 ? nil : hue, whiteness, blackness]
    case .lch:
      let lab = ColorConversion.lab(ofSRGB: rgb)
      let (chroma, hue) = ColorConversion.polar(a: lab.1, b: lab.2)
      return [lab.0, chroma, chroma < Self.lchChromaEpsilon ? nil : hue]
    case .oklch:
      let lab = ColorConversion.oklab(ofSRGB: rgb)
      let (chroma, hue) = ColorConversion.polar(a: lab.1, b: lab.2)
      return [lab.0, chroma, chroma < Self.oklchChromaEpsilon ? nil : hue]
    default:
      let c = ColorConversion.components(ofSRGB: rgb, in: cssColorSpace!)
      return [c.0, c.1, c.2]
    }
  }

  /// The red, green and blue of sRGB of a color of the components in the space, which can be outside 0 to 1.
  func sRGB(ofComponents c: [Double]) -> ColorConversion.Vector {
    switch self {
    case .sRGB: return (c[0], c[1], c[2])
    case .lab: return ColorConversion.sRGB(lightness: c[0], a: c[1], b: c[2])
    case .oklab: return ColorConversion.sRGB(oklabLightness: c[0], a: c[1], b: c[2])
    case .hsl: return ColorConversion.sRGB(hue: c[0], saturation: c[1], lightness: c[2])
    case .hwb: return ColorConversion.sRGB(hue: c[0], whiteness: c[1], blackness: c[2])
    case .lch:
      let (a, b) = ColorConversion.ab(chroma: c[1], hue: c[2])
      return ColorConversion.sRGB(lightness: c[0], a: a, b: b)
    case .oklch:
      let (a, b) = ColorConversion.ab(chroma: c[1], hue: c[2])
      return ColorConversion.sRGB(oklabLightness: c[0], a: a, b: b)
    default:
      return ColorConversion.sRGB((c[0], c[1], c[2]), in: cssColorSpace!)
    }
  }

  /// The space of `color()` that the space is, or `nil` for one that isn't.
  private var cssColorSpace: CSSColorSpace? {
    CSSColorSpace(rawValue: rawValue)
  }

  /// The chroma under which a color has no hue, which absorbs the errors of the conversions of grays.
  private static let lchChromaEpsilon = 0.0015 * 375
  private static let oklchChromaEpsilon = 0.0015
}

/// How `color-mix()` interpolates hues, which go around the circle of hues in one of two directions.
enum HueInterpolationMethod: String, Sendable {
  case shorter
  case longer
  case increasing
  case decreasing
}

extension ColorConversion {
  /// The red, green, blue and alpha of sRGB of two colors of sRGB mixed in a space, as `color-mix()` mixes them, or
  /// `nil` for percentages that don't make a mix.
  ///
  /// The components are interpolated with the alpha premultiplied, except for the hue, which goes around the circle
  /// of hues in the direction of the method. A component that's missing in one color, which is `nil`, such as the
  /// hue of a gray or a component that's `none`, takes the value of the other, and is 0 if both miss it, as CSS
  /// Color 4 specifies. So is the alpha.
  ///
  /// - Parameters:
  ///   - color1: The components of the first color in the space, and its alpha.
  ///   - percentage1: The percentage of the first color, or `nil` if it's omitted.
  ///   - color2: The components of the second color in the space, and its alpha.
  ///   - percentage2: The percentage of the second color, or `nil` if it's omitted.
  static func mix(
    _ color1: (components: [Double?], alpha: Double?), _ percentage1: Double?,
    _ color2: (components: [Double?], alpha: Double?), _ percentage2: Double?, in space: ColorMixSpace,
    hue method: HueInterpolationMethod
  ) -> (rgb: Vector, alpha: Double)? {
    guard let (w1, w2, alphaMultiplier) = mixWeights(percentage1, percentage2) else { return nil }

    let c1 = color1.components
    let c2 = color2.components
    let alpha1 = color1.alpha ?? color2.alpha ?? 0
    let alpha2 = color2.alpha ?? color1.alpha ?? 0
    let alpha = alpha1 * w1 + alpha2 * w2
    var mixed = [Double](repeating: 0, count: 3)
    for index in 0..<3 {
      let v1 = c1[index] ?? c2[index] ?? 0
      let v2 = c2[index] ?? c1[index] ?? 0
      if index == space.hueIndex {
        let (from, to) = hues(v1, v2, method)
        let hue = (from * w1 + to * w2).truncatingRemainder(dividingBy: 360)
        mixed[index] = hue < 0 ? hue + 360 : hue
      } else {
        mixed[index] = alpha == 0 ? v1 * w1 + v2 * w2 : (v1 * alpha1 * w1 + v2 * alpha2 * w2) / alpha
      }
    }
    return (space.sRGB(ofComponents: mixed), alpha * alphaMultiplier)
  }

  /// The weights of the two colors of `color-mix()`, which add up to 1, and the factor of its alpha, or `nil` for
  /// percentages that don't make a mix: one outside 0% to 100%, or a sum of 0%.
  ///
  /// Two omitted percentages are 50% each, and one is 100% minus the other. Percentages that don't add up to 100%
  /// are scaled to, and a sum under 100% lowers the alpha of the mix.
  static func mixWeights(_ percentage1: Double?, _ percentage2: Double?) -> (Double, Double, Double)? {
    let p1: Double
    let p2: Double
    switch (percentage1, percentage2) {
    case (nil, nil): (p1, p2) = (50, 50)
    case (let p?, nil): (p1, p2) = (p, 100 - p)
    case (nil, let p?): (p1, p2) = (100 - p, p)
    case (let a?, let b?): (p1, p2) = (a, b)
    }
    let sum = p1 + p2
    guard (0...100).contains(p1), (0...100).contains(p2), sum > 0 else { return nil }
    return (p1 / sum, p2 / sum, min(sum, 100) / 100)
  }

  /// Two hues from 0 to 360, one of which is moved by 360 degrees so that interpolating between them goes in the
  /// direction of the method.
  private static func hues(
    _ h1: Double, _ h2: Double, _ method: HueInterpolationMethod
  ) -> (Double, Double) {
    func normalized(_ h: Double) -> Double {
      let h = h.truncatingRemainder(dividingBy: 360)
      return h < 0 ? h + 360 : h
    }
    var (h1, h2) = (normalized(h1), normalized(h2))
    let difference = h2 - h1
    switch method {
    case .shorter:
      if difference > 180 { h1 += 360 } else if difference < -180 { h2 += 360 }
    case .longer:
      if 0 < difference, difference < 180 { h1 += 360 } else if -180 < difference, difference <= 0 { h2 += 360 }
    case .increasing:
      if h2 < h1 { h2 += 360 }
    case .decreasing:
      if h1 < h2 { h1 += 360 }
    }
    return (h1, h2)
  }
}
