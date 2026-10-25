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

  /// The length, or zero in its unit if it's negative.
  var nonNegative: SVGLength {
    magnitude < 0 ? with(magnitude: 0) : self
  }

  /// The length in pixels, if its unit is absolute. A number is in pixels.
  fileprivate var absolutePixels: CGFloat? {
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
  fileprivate func with(magnitude value: CGFloat) -> SVGLength {
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

/// Transform lists are interpolated as CSS Transforms 2 specifies. The shorter list, or `none`, is padded with
/// identity functions of the kinds of the other list, and functions of the same kind are interpolated one by one.
/// From the first pair of functions of different kinds, or of lengths in units that can't be interpolated, the rest
/// of both lists are interpolated as matrices, which isn't possible for lengths relative to the reference box or the
/// viewport, and the lists are then discrete.
extension TransformList: Animatable {
  func interpolated(to other: TransformList, progress: Double) -> TransformList? {
    let from = functions + other.functions.dropFirst(functions.count).map(\.identity)
    let to = other.functions + functions.dropFirst(other.functions.count).map(\.identity)
    var result = [TransformFunction]()
    for index in from.indices {
      if let function = from[index].interpolated(to: to[index], progress: progress) {
        result.append(function)
        continue
      }
      guard let fromMatrix = absoluteMatrix(of: from[index...]), let toMatrix = absoluteMatrix(of: to[index...]) else {
        return nil
      }
      result.append(.matrix(DecomposedMatrix(fromMatrix).interpolated(to: DecomposedMatrix(toMatrix), progress: progress)))
      break
    }
    return TransformList(functions: result)
  }

  /// The functions of both lists, as CSS Transforms 2 adds transform lists.
  func adding(_ other: TransformList) -> TransformList? {
    TransformList(functions: functions + other.functions)
  }

  func pacedDistance(to _: TransformList) -> Double? {
    nil
  }
}

extension TransformFunction {
  /// The function of the same kind that doesn't transform. A length of a translation has the unit of the length of
  /// the function, so that it's interpolated with it.
  fileprivate var identity: TransformFunction {
    switch self {
    case .translate(let x, let y): .translate(x.with(magnitude: 0), y.with(magnitude: 0))
    case .scale: .scale(1, 1)
    case .rotate: .rotate(0)
    case .skew: .skew(0, 0)
    case .matrix: .matrix(.identity)
    }
  }

  /// The function between two functions of the same kind, or `nil` if their kinds are different or their lengths
  /// can't be interpolated.
  fileprivate func interpolated(to other: TransformFunction, progress: Double) -> TransformFunction? {
    func number(_ from: Double, _ to: Double) -> Double { from + (to - from) * progress }
    switch (self, other) {
    case (.translate(let x, let y), .translate(let toX, let toY)):
      guard let x = x.interpolated(to: toX, progress: progress), let y = y.interpolated(to: toY, progress: progress)
      else { return nil }
      return .translate(x, y)
    case (.scale(let x, let y), .scale(let toX, let toY)):
      return .scale(number(x, toX), number(y, toY))
    case (.rotate(let angle), .rotate(let toAngle)):
      return .rotate(number(angle, toAngle))
    case (.skew(let x, let y), .skew(let toX, let toY)):
      return .skew(number(x, toX), number(y, toY))
    case (.matrix(let matrix), .matrix(let toMatrix)):
      return .matrix(DecomposedMatrix(matrix).interpolated(to: DecomposedMatrix(toMatrix), progress: progress))
    default:
      return nil
    }
  }
}

/// The matrix of functions, or `nil` if a length of a translation isn't absolute.
private func absoluteMatrix(of functions: ArraySlice<TransformFunction>) -> CGAffineTransform? {
  var transform = CGAffineTransform.identity
  for function in functions {
    if case .translate(let x, let y) = function {
      guard let x = x.absolutePixels, let y = y.absolutePixels else { return nil }
      transform = transform.translatedBy(x: x, y: y)
    } else {
      transform = function.applied(to: transform, box: .zero, context: NoLengthContext())
    }
  }
  return transform
}

/// A context for functions that have no lengths.
private struct NoLengthContext: SVGLengthContext {
  var viewBoxSize: CGSize { .zero }
  var font: SVGUIFont? { nil }
  var textScale: Double { 1 }
  var rootFont: SVGUIFont? { nil }
  var viewPort: CGRect { .zero }
  var writingMode: WritingMode? { nil }
}

/// A 2D matrix decomposed as CSS Transforms 1 specifies for interpolating it: the matrix is a scale, then a
/// rotation, then the rest, then a translation.
private struct DecomposedMatrix {
  var translation: CGPoint
  var scale: CGPoint
  /// The angle of the rotation, in degrees.
  var angle: Double
  var m11: Double
  var m12: Double
  var m21: Double
  var m22: Double

  init(_ matrix: CGAffineTransform) {
    var row0 = CGPoint(x: matrix.a, y: matrix.b)
    var row1 = CGPoint(x: matrix.c, y: matrix.d)
    translation = CGPoint(x: matrix.tx, y: matrix.ty)
    scale = CGPoint(x: hypot(row0.x, row0.y), y: hypot(row1.x, row1.y))
    // If the determinant is negative, one axis was flipped: flip the axis with the smaller part along itself.
    if row0.x * row1.y - row0.y * row1.x < 0 {
      if row0.x < row1.y { scale.x = -scale.x } else { scale.y = -scale.y }
    }
    if scale.x != 0 { row0 = CGPoint(x: row0.x / scale.x, y: row0.y / scale.x) }
    if scale.y != 0 { row1 = CGPoint(x: row1.x / scale.y, y: row1.y / scale.y) }
    let radians = atan2(row0.y, row0.x)
    if radians != 0 {
      let sine = -row0.y
      let cosine = row0.x
      (row0, row1) = (
        CGPoint(x: cosine * row0.x + sine * row1.x, y: cosine * row0.y + sine * row1.y),
        CGPoint(x: -sine * row0.x + cosine * row1.x, y: -sine * row0.y + cosine * row1.y)
      )
    }
    angle = radians * 180 / .pi
    (m11, m12, m21, m22) = (row0.x, row0.y, row1.x, row1.y)
  }

  func interpolated(to other: DecomposedMatrix, progress: Double) -> CGAffineTransform {
    var from = self
    var to = other
    // If the x axis of one is flipped, and the y axis of the other, the flips are a rotation instead.
    if (from.scale.x < 0 && to.scale.y < 0) || (from.scale.y < 0 && to.scale.x < 0) {
      from.scale = CGPoint(x: -from.scale.x, y: -from.scale.y)
      from.angle += from.angle < 0 ? 180 : -180
    }
    // Don't rotate the long way around.
    if from.angle == 0 { from.angle = 360 }
    if to.angle == 0 { to.angle = 360 }
    if abs(from.angle - to.angle) > 180 {
      if from.angle > to.angle { from.angle -= 360 } else { to.angle -= 360 }
    }
    func number(_ from: Double, _ to: Double) -> Double { from + (to - from) * progress }
    return DecomposedMatrix(
      translation: CGPoint(
        x: number(from.translation.x, to.translation.x), y: number(from.translation.y, to.translation.y)),
      scale: CGPoint(x: number(from.scale.x, to.scale.x), y: number(from.scale.y, to.scale.y)),
      angle: number(from.angle, to.angle), m11: number(from.m11, to.m11), m12: number(from.m12, to.m12),
      m21: number(from.m21, to.m21), m22: number(from.m22, to.m22)
    ).matrix
  }

  /// The matrix that the parts make.
  var matrix: CGAffineTransform {
    let radians = angle * .pi / 180
    // The rotation after the scale, as the columns of their matrix.
    let x = CGPoint(x: scale.x * cos(radians), y: scale.x * sin(radians))
    let y = CGPoint(x: -scale.y * sin(radians), y: scale.y * cos(radians))
    return CGAffineTransform(
      a: m11 * x.x + m21 * x.y, b: m12 * x.x + m22 * x.y, c: m11 * y.x + m21 * y.y, d: m12 * y.x + m22 * y.y,
      tx: translation.x, ty: translation.y)
  }

  private init(
    translation: CGPoint, scale: CGPoint, angle: Double, m11: Double, m12: Double, m21: Double, m22: Double
  ) {
    self.translation = translation
    self.scale = scale
    self.angle = angle
    self.m11 = m11
    self.m12 = m12
    self.m21 = m21
    self.m22 = m22
  }
}

/// Transform origins are animated as two lengths.
extension TransformOrigin: Animatable {
  func interpolated(to other: TransformOrigin, progress: Double) -> TransformOrigin? {
    guard let x = x.interpolated(to: other.x, progress: progress), let y = y.interpolated(to: other.y, progress: progress)
    else { return nil }
    return TransformOrigin(x: x, y: y)
  }

  func adding(_ other: TransformOrigin) -> TransformOrigin? {
    guard let x = x.adding(other.x), let y = y.adding(other.y) else { return nil }
    return TransformOrigin(x: x, y: y)
  }

  func pacedDistance(to other: TransformOrigin) -> Double? {
    guard let x = x.pacedDistance(to: other.x), let y = y.pacedDistance(to: other.y) else { return nil }
    return hypot(x, y)
  }
}
