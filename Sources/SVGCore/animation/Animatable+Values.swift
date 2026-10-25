import CoreGraphics
import Foundation

/// Lengths are animated when they have the same unit or are both absolute. A percentage or a length relative to
/// the viewport isn't animated with a length in another unit, since their sum isn't known until the render tree
/// is built.
extension SVGLength: Animatable {
  func interpolated(to other: SVGLength, progress: Double) -> SVGLength? {
    combined(with: other) { $0 + ($1 - $0) * progress }
  }

  func adding(_ other: SVGLength) -> SVGLength? {
    combined(with: other, +)
  }

  func pacedDistance(to other: SVGLength) -> Double? {
    if hasSameUnit(as: other) {
      return magnitude.pacedDistance(to: other.magnitude)
    }
    guard let pixels = absolutePixels, let otherPixels = other.absolutePixels else { return nil }
    return pixels.pacedDistance(to: otherPixels)
  }

  /// The length that combines the numbers of two lengths, in their unit, or in pixels if their units are
  /// different absolute units.
  private func combined(with other: SVGLength, _ combine: (CGFloat, CGFloat) -> CGFloat) -> SVGLength? {
    if hasSameUnit(as: other) {
      return with(magnitude: combine(magnitude, other.magnitude))
    }
    guard let pixels = absolutePixels, let otherPixels = other.absolutePixels else { return nil }
    return .pixel(combine(pixels, otherPixels))
  }

  private func hasSameUnit(as other: SVGLength) -> Bool {
    with(magnitude: 0) == other.with(magnitude: 0)
  }

  /// The length in pixels, if its unit is absolute. A number is in pixels.
  private var absolutePixels: CGFloat? {
    switch self {
    case .number(let value), .pixel(let value): value
    case .centimeters(let value): value * Self.pixelsPerInch / 2.54
    case .millimeters(let value): value * Self.pixelsPerInch / 25.4
    case .q(let value): value * Self.pixelsPerInch / 101.6
    case .inches(let value): value * Self.pixelsPerInch
    case .points(let value): value * Self.pixelsPerInch / 72
    case .picas(let value): value * Self.pixelsPerInch / 6
    default: nil
    }
  }

  /// The number of the length in its unit.
  private var magnitude: CGFloat {
    switch self {
    case .number(let value), .pixel(let value), .percent(let value), .ems(let value), .rems(let value),
      .exs(let value), .centimeters(let value), .millimeters(let value), .inches(let value), .points(let value),
      .picas(let value), .chs(let value), .ic(let value), .lhs(let value), .rlhs(let value), .vw(let value),
      .vh(let value), .vi(let value), .vb(let value), .vmin(let value), .vmax(let value), .q(let value):
      value
    }
  }

  /// The length with the same unit and another number.
  private func with(magnitude value: CGFloat) -> SVGLength {
    switch self {
    case .number: .number(value)
    case .pixel: .pixel(value)
    case .percent: .percent(value)
    case .ems: .ems(value)
    case .rems: .rems(value)
    case .exs: .exs(value)
    case .centimeters: .centimeters(value)
    case .millimeters: .millimeters(value)
    case .inches: .inches(value)
    case .points: .points(value)
    case .picas: .picas(value)
    case .chs: .chs(value)
    case .ic: .ic(value)
    case .lhs: .lhs(value)
    case .rlhs: .rlhs(value)
    case .vw: .vw(value)
    case .vh: .vh(value)
    case .vi: .vi(value)
    case .vb: .vb(value)
    case .vmin: .vmin(value)
    case .vmax: .vmax(value)
    case .q: .q(value)
    }
  }
}

/// Colors are interpolated in premultiplied sRGB, as CSS Color 4 specifies for colors in the legacy syntax.
extension SVGColor: Animatable {
  func interpolated(to other: SVGColor, progress: Double) -> SVGColor? {
    guard let from = components, let to = other.components else { return nil }
    let alpha = Self.clamped(from.alpha + (to.alpha - from.alpha) * progress)
    guard alpha > 0 else { return Self.color(red: 0, green: 0, blue: 0, alpha: 0) }
    func channel(_ from: Double, _ to: Double, _ fromAlpha: Double, _ toAlpha: Double) -> Double {
      Self.clamped((from * fromAlpha + (to * toAlpha - from * fromAlpha) * progress) / alpha)
    }
    return Self.color(
      red: channel(from.red, to.red, from.alpha, to.alpha),
      green: channel(from.green, to.green, from.alpha, to.alpha),
      blue: channel(from.blue, to.blue, from.alpha, to.alpha), alpha: alpha)
  }

  func adding(_ other: SVGColor) -> SVGColor? {
    guard let from = components, let to = other.components else { return nil }
    return Self.color(
      red: Self.clamped(from.red + to.red), green: Self.clamped(from.green + to.green),
      blue: Self.clamped(from.blue + to.blue), alpha: Self.clamped(from.alpha + to.alpha))
  }

  func pacedDistance(to other: SVGColor) -> Double? {
    guard let from = components, let to = other.components else { return nil }
    let differences = [to.red - from.red, to.green - from.green, to.blue - from.blue, to.alpha - from.alpha]
    return sqrt(differences.reduce(0) { $0 + $1 * $1 })
  }

  /// The red, green, blue and alpha components from 0 to 1, or `nil` for a color that isn't a color value.
  var components: (red: Double, green: Double, blue: Double, alpha: Double)? {
    guard let components = toCGColor(opacity: 1)?.components, components.count == 4 else { return nil }
    return (red: components[0], green: components[1], blue: components[2], alpha: components[3])
  }

  private static func color(red: Double, green: Double, blue: Double, alpha: Double) -> SVGColor {
    .rgba(SVGRGBAColor(r: .absolute(red * 255), g: .absolute(green * 255), b: .absolute(blue * 255), a: alpha))
  }

  private static func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}

/// A color value is animated as a color. `currentColor` isn't animated, so the caller resolves it to the color of
/// the element first.
extension ColorValue: Animatable {
  func interpolated(to other: ColorValue, progress: Double) -> ColorValue? {
    guard case .color(let from) = self, case .color(let to) = other,
      let color = from.interpolated(to: to, progress: progress)
    else { return nil }
    return .color(color)
  }

  func adding(_ other: ColorValue) -> ColorValue? {
    guard case .color(let from) = self, case .color(let to) = other, let color = from.adding(to) else { return nil }
    return .color(color)
  }

  func pacedDistance(to other: ColorValue) -> Double? {
    guard case .color(let from) = self, case .color(let to) = other else { return nil }
    return from.pacedDistance(to: to)
  }
}

/// A paint is animated when both paints are colors. A change to or from `none` or a paint server is discrete.
/// `currentColor` isn't animated, so the caller resolves it to the color of the element first.
extension Paint: Animatable {
  func interpolated(to other: Paint, progress: Double) -> Paint? {
    guard case .color(let from) = self, case .color(let to) = other,
      let color = from.interpolated(to: to, progress: progress)
    else { return nil }
    return .color(color)
  }

  func adding(_ other: Paint) -> Paint? {
    guard case .color(let from) = self, case .color(let to) = other, let color = from.adding(to) else { return nil }
    return .color(color)
  }

  func pacedDistance(to other: Paint) -> Double? {
    guard case .color(let from) = self, case .color(let to) = other else { return nil }
    return from.pacedDistance(to: to)
  }
}

/// The lengths of `stroke-dasharray` are animated as a repeatable list: both lists repeat to the least common
/// multiple of their lengths, and the lengths are interpolated one by one. An empty list is `none`, which isn't
/// animated.
extension [CGFloat]: Animatable {
  func interpolated(to other: [CGFloat], progress: Double) -> [CGFloat]? {
    guard let (from, to) = Self.repeated(self, other) else { return nil }
    return zip(from, to).map { $0 + ($1 - $0) * progress }
  }

  func adding(_ other: [CGFloat]) -> [CGFloat]? {
    guard !isEmpty, count == other.count else { return nil }
    return zip(self, other).map(+)
  }

  func pacedDistance(to other: [CGFloat]) -> Double? {
    guard let (from, to) = Self.repeated(self, other) else { return nil }
    return sqrt(zip(from, to).reduce(0) { $0 + Double(($1.1 - $1.0) * ($1.1 - $1.0)) })
  }

  /// Both lists repeated to the least common multiple of their lengths, or `nil` if either is empty.
  private static func repeated(_ a: [CGFloat], _ b: [CGFloat]) -> ([CGFloat], [CGFloat])? {
    guard !a.isEmpty, !b.isEmpty else { return nil }
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    let count = a.count / gcd(a.count, b.count) * b.count
    return ((0..<count).map { a[$0 % a.count] }, (0..<count).map { b[$0 % b.count] })
  }
}

/// Font weights are animated as numbers. `normal` is 400 and `bold` is 700.
extension SVGUIFont.Weight: Animatable {
  func interpolated(to other: SVGUIFont.Weight, progress: Double) -> SVGUIFont.Weight? {
    guard let from = number, let to = other.number else { return nil }
    return .number(from + (to - from) * progress)
  }

  func adding(_ other: SVGUIFont.Weight) -> SVGUIFont.Weight? {
    guard let from = number, let to = other.number else { return nil }
    return .number(from + to)
  }

  func pacedDistance(to other: SVGUIFont.Weight) -> Double? {
    guard let from = number, let to = other.number else { return nil }
    return abs(to - from)
  }

  /// The weight as a number, or `nil` for a weight relative to the parent's.
  private var number: Double? {
    switch self {
    case .normal: 400
    case .bold: 700
    case .number(let value): value
    case .lighter, .bolder: nil
    }
  }
}

/// Font sizes are animated as lengths. A keyword isn't animated.
extension SVGUIFont.Size: Animatable {
  func interpolated(to other: SVGUIFont.Size, progress: Double) -> SVGUIFont.Size? {
    guard case .length(let from) = self, case .length(let to) = other,
      let length = from.interpolated(to: to, progress: progress)
    else { return nil }
    return .length(length)
  }

  func adding(_ other: SVGUIFont.Size) -> SVGUIFont.Size? {
    guard case .length(let from) = self, case .length(let to) = other, let length = from.adding(to) else {
      return nil
    }
    return .length(length)
  }

  func pacedDistance(to other: SVGUIFont.Size) -> Double? {
    guard case .length(let from) = self, case .length(let to) = other else { return nil }
    return from.pacedDistance(to: to)
  }
}
