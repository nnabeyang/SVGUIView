import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// Whether two numbers are equal, apart from the error of the arithmetic.
private func isClose(_ a: Double, _ b: Double) -> Bool {
  abs(a - b) < 1e-9
}

private func color(_ text: String) throws -> SVGColor {
  try #require(SVGAttributeScanner.parseColor(description: text))
}

/// Whether the paint is a paint server with the ID.
private func isURL(_ paint: Paint, _ id: String) -> Bool {
  if case .url(id, _) = paint { true } else { false }
}

/// Whether the color has the components, from 0 to 1.
private func matches(_ color: SVGColor?, _ expected: (Double, Double, Double, Double)) -> Bool {
  guard let components = color?.components else { return false }
  return isClose(components.red, expected.0) && isClose(components.green, expected.1)
    && isClose(components.blue, expected.2) && isClose(components.alpha, expected.3)
}

@Suite("Animatable values")
struct AnimatableTests {
  @Test("numbers are interpolated linearly, also outside 0 to 1", arguments: [(0.0, 0.0), (0.25, 2.5), (1.5, 15)])
  func numbers(progress: Double, value: Double) {
    #expect(0.0.interpolated(to: 10, progress: progress) == value)
    #expect(CGFloat(0).interpolated(to: 10, progress: progress) == CGFloat(value))
  }

  @Test("numbers are added and measured")
  func numberSumAndDistance() {
    #expect(2.0.adding(3) == 5)
    #expect(2.0.pacedDistance(to: -3) == 5)
  }

  @Test("values that can't be interpolated step halfway")
  func discreteSteps() {
    #expect(!isURL(Paint.none.animated(to: .url("#a", fallback: nil), progress: 0.49), "#a"))
    #expect(isURL(Paint.none.animated(to: .url("#a", fallback: nil), progress: 0.5), "#a"))
  }

  /// Lengths and their interpolations halfway, or `nil` where they can't be interpolated.
  private static let lengths: [(SVGLength, SVGLength, SVGLength?)] = [
    (.pixel(10), .pixel(20), .pixel(15)),
    (.number(10), .pixel(20), .pixel(15)),
    (.percent(10), .percent(20), .percent(15)),
    (.centimeters(1), .centimeters(2), .centimeters(1.5)),
    (.vw(10), .vw(20), .vw(15)),
    (.inches(1), .pixel(48), .pixel(72)),
    (.points(72), .picas(12), .pixel(144)),
    (.percent(10), .pixel(20), nil),
    (.vw(10), .pixel(20), nil),
  ]

  @Test("lengths are interpolated in the same unit or in pixels", arguments: lengths)
  func lengthInterpolation(from: SVGLength, to: SVGLength, halfway: SVGLength?) {
    #expect(from.interpolated(to: to, progress: 0.5) == halfway)
  }

  @Test("lengths are added and measured like they're interpolated")
  func lengthSumAndDistance() {
    #expect(SVGLength.percent(10).adding(.percent(20)) == .percent(30))
    #expect(SVGLength.inches(1).adding(.pixel(4)) == .pixel(100))
    #expect(SVGLength.percent(10).adding(.pixel(4)) == nil)
    #expect(SVGLength.inches(1).pacedDistance(to: .pixel(100)) == 4)
    #expect(SVGLength.percent(10).pacedDistance(to: .pixel(4)) == nil)
  }

  /// Colors and the components of their interpolations halfway.
  private static let colors: [(String, String, (Double, Double, Double, Double))] = [
    ("red", "blue", (0.5, 0, 0.5, 1)),
    ("#f00", "#0000ff", (0.5, 0, 0.5, 1)),
    ("white", "rgb(0, 0, 0)", (0.5, 0.5, 0.5, 1)),
    ("rgba(255, 0, 0, 1)", "rgba(0, 0, 255, 0)", (1, 0, 0, 0.5)),
    ("rgba(255, 0, 0, 0.5)", "rgba(0, 0, 255, 0.25)", (2.0 / 3, 0, 1.0 / 3, 0.375)),
    ("rgba(255, 0, 0, 0)", "rgba(0, 0, 255, 0)", (0, 0, 0, 0)),
  ]

  @Test("colors are interpolated in premultiplied sRGB", arguments: colors)
  func colorInterpolation(from: String, to: String, halfway: (Double, Double, Double, Double)) throws {
    #expect(matches(try color(from).interpolated(to: color(to), progress: 0.5), halfway))
  }

  @Test("colors are kept in their range when the progress overshoots")
  func colorOvershoot() throws {
    #expect(matches(try color("red").interpolated(to: color("blue"), progress: 1.5), (0, 0, 1, 1)))
  }

  @Test("colors are added and measured by their components")
  func colorSumAndDistance() throws {
    #expect(matches(try color("rgb(255, 128, 0)").adding(color("rgb(255, 0, 255)")), (1, 128.0 / 255, 1, 1)))
    let distance = try #require(try color("black").pacedDistance(to: color("white")))
    #expect(isClose(distance, sqrt(3)))
  }

  @Test("paints are interpolated only between colors")
  func paints() throws {
    let red = Paint.color(try color("red"))
    let blue = Paint.color(try color("blue"))
    guard case .color(let halfway) = try #require(red.interpolated(to: blue, progress: 0.5)) else {
      Issue.record("halfway isn't a color")
      return
    }
    #expect(matches(halfway, (0.5, 0, 0.5, 1)))
    #expect(red.interpolated(to: .url("#a", fallback: nil), progress: 0.5) == nil)
    #expect(red.interpolated(to: .none, progress: 0.5) == nil)
    #expect(red.interpolated(to: .currentColor, progress: 0.5) == nil)
    #expect(ColorValue.color(try color("red")).interpolated(to: .currentColor, progress: 0.5) == nil)
  }

  /// Dash arrays and their interpolations halfway, or `nil` where they can't be interpolated.
  private static let dashArrays: [([CGFloat], [CGFloat], [CGFloat]?)] = [
    ([1, 2], [3, 4], [2, 3]),
    ([1, 2], [3, 4, 5], [2, 3, 3, 2.5, 2.5, 3.5]),
    ([1], [3, 5], [2, 3]),
    ([], [3, 4], nil),
  ]

  @Test("dash arrays repeat to a common length and are interpolated one by one", arguments: dashArrays)
  func dashArrayInterpolation(from: [CGFloat], to: [CGFloat], halfway: [CGFloat]?) {
    #expect(from.interpolated(to: to, progress: 0.5) == halfway)
  }

  @Test("visibility stays visible between visible and another value")
  func visibility() {
    #expect(CSSVisibility.visible.animated(to: .hidden, progress: 0) == .visible)
    #expect(CSSVisibility.visible.animated(to: .hidden, progress: 0.9) == .visible)
    #expect(CSSVisibility.visible.animated(to: .hidden, progress: 1) == .hidden)
    #expect(CSSVisibility.hidden.animated(to: .visible, progress: 0) == .hidden)
    #expect(CSSVisibility.hidden.animated(to: .visible, progress: 0.1) == .visible)
    #expect(CSSVisibility.hidden.animated(to: .collapse, progress: 0.49) == .hidden)
    #expect(CSSVisibility.hidden.animated(to: .collapse, progress: 0.5) == .collapse)
  }

  @Test("missing values such as auto aren't interpolated")
  func optionals() {
    let auto: SVGLength? = nil
    #expect(SVGLength?.some(.pixel(10)).interpolated(to: .pixel(20), progress: 0.5) == .some(.pixel(15)))
    #expect(auto.interpolated(to: .pixel(20), progress: 0.5) == nil)
    #expect(auto.animated(to: .pixel(20), progress: 0.5) == .pixel(20))
  }

  @Test("font weights are interpolated as numbers")
  func fontWeights() throws {
    guard case .number(let weight) = try #require(SVGUIFont.Weight.normal.interpolated(to: .bold, progress: 0.5))
    else {
      Issue.record("the weight isn't a number")
      return
    }
    #expect(weight == 550)
    #expect(SVGUIFont.Weight.lighter.interpolated(to: .bold, progress: 0.5) == nil)
  }

  @Test("font sizes are interpolated as lengths")
  func fontSizes() throws {
    guard
      case .length(let size) = try #require(
        SVGUIFont.Size.length(.pixel(10)).interpolated(to: .length(.pixel(20)), progress: 0.5))
    else {
      Issue.record("the size isn't a length")
      return
    }
    #expect(size == .pixel(15))
    #expect(SVGUIFont.Size.medium.interpolated(to: .length(.pixel(20)), progress: 0.5) == nil)
  }

  /// Transform lists that are interpolated function by function, and their interpolations halfway.
  private static let transformLists: [([TransformFunction], [TransformFunction], [TransformFunction])] = [
    ([.translate(.pixel(10), .pixel(0))], [.translate(.pixel(20), .pixel(10))], [.translate(.pixel(15), .pixel(5))]),
    ([], [.rotate(90)], [.rotate(45)]),
    ([.scale(2, 2)], [], [.scale(1.5, 1.5)]),
    ([], [.translate(.percent(50), .number(0))], [.translate(.percent(25), .number(0))]),
    (
      [.translate(.percent(10), .number(0)), .rotate(0)], [.translate(.percent(30), .number(0))],
      [.translate(.percent(20), .number(0)), .rotate(0)]
    ),
    ([.skew(10, 0)], [.skew(30, 20)], [.skew(20, 10)]),
  ]

  @Test("transform lists are interpolated function by function", arguments: transformLists)
  func transformListInterpolation(from: [TransformFunction], to: [TransformFunction], halfway: [TransformFunction]) {
    #expect(
      TransformList(functions: from).interpolated(to: TransformList(functions: to), progress: 0.5)
        == TransformList(functions: halfway))
  }

  @Test("transform lists are interpolated as matrices from a pair of functions of different kinds")
  func transformMatrixInterpolation() throws {
    // A translation and a rotation of 90 degrees halfway to the identity, which is a rotation of 45 degrees.
    let list = try #require(
      TransformList(functions: [.translate(.pixel(10), .pixel(0)), .rotate(90)])
        .interpolated(to: TransformList(functions: [.scale(1, 1)]), progress: 0.5))
    guard list.functions.count == 1, case .matrix(let matrix) = list.functions[0] else {
      Issue.record("The list isn't a matrix: \(list)")
      return
    }
    expectClose(matrix, CGAffineTransform(translationX: 5, y: 0).rotated(by: .pi / 4))

    let scale = try #require(
      TransformList(functions: [.rotate(0)]).interpolated(to: TransformList(functions: [.scale(2, 2)]), progress: 0.5))
    expectClose(try #require(Self.matrix(scale)), CGAffineTransform(scaleX: 1.5, y: 1.5))

    // Matrices are interpolated as matrices also when both are matrices.
    let to = CGAffineTransform(translationX: 10, y: 20).rotated(by: .pi / 2)
    let matrices = try #require(
      TransformList(functions: [.matrix(.identity)]).interpolated(
        to: TransformList(functions: [.matrix(to)]), progress: 0.5))
    expectClose(try #require(Self.matrix(matrices)), CGAffineTransform(translationX: 5, y: 10).rotated(by: .pi / 4))
  }

  @Test("transform lists with lengths relative to the box are discrete when they're interpolated as matrices")
  func transformListsDiscrete() {
    let from = TransformList(functions: [.translate(.percent(10), .number(0))])
    let to = TransformList(functions: [.rotate(90)])
    #expect(from.interpolated(to: to, progress: 0.5) == nil)
    #expect(from.animated(to: to, progress: 0.25) == from)
    #expect(from.adding(to) == TransformList(functions: from.functions + to.functions))
  }

  @Test("transform origins are interpolated as two lengths")
  func transformOrigins() {
    let from = TransformOrigin(x: .percent(0), y: .percent(0))
    #expect(
      from.interpolated(to: TransformOrigin(x: .percent(100), y: .percent(50)), progress: 0.5)
        == TransformOrigin(x: .percent(50), y: .percent(25)))
    #expect(from.interpolated(to: TransformOrigin(x: .pixel(10), y: .percent(50)), progress: 0.5) == nil)
  }

  private static func matrix(_ list: TransformList) -> CGAffineTransform? {
    guard list.functions.count == 1, case .matrix(let matrix) = list.functions[0] else { return nil }
    return matrix
  }

  private func expectClose(
    _ matrix: CGAffineTransform, _ expected: CGAffineTransform, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let values = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty]
    let expectedValues = [expected.a, expected.b, expected.c, expected.d, expected.tx, expected.ty]
    #expect(
      zip(values, expectedValues).allSatisfy { isClose($0, $1) }, "\(matrix) isn't \(expected)",
      sourceLocation: sourceLocation)
  }

  /// Path data, and their interpolations halfway, or `nil` where they're discrete.
  private static let pathData: [(String, String, String?)] = [
    ("M0 0 L10 0 C0 0 10 10 20 20", "M10 10 L30 0 C10 10 20 30 40 40", "M5 5 L20 0 C5 5 15 20 30 30"),
    ("M0 0 h10 v10 z", "M10 0 h20 v-10 z", "M5 0 h15 v0 z"),
    // A relative command and its absolute form are interpolated in absolute coordinates.
    ("M10 10 l10 0", "M10 10 L40 10", "M10 10 L30 10"),
    // The flags of an arc are 1 for a number that isn't zero.
    ("M0 0 A10 10 0 0 0 20 0", "M0 0 A20 20 90 1 1 40 0", "M0 0 A15 15 45 1 1 30 0"),
    ("M0 0 L10 10", "M0 0 Q10 10 20 20", nil),
    ("M0 0 L10 10", "M0 0 L10 10 L20 20", nil),
    ("M0 0 L10 10", "", nil),
  ]

  @Test("path data is interpolated number by number when it has the same commands", arguments: pathData)
  func pathDataInterpolation(from: String, to: String, halfway: String?) {
    #expect(PathData(from).interpolated(to: PathData(to), progress: 0.5) == halfway.map(PathData.init))
  }

  @Test("path data is made absolute with the current point and the start of the subpath")
  func absolutePathData() {
    let relative = PathData("m10 10 h10 v10 l-10 0 z m5 5 c1 1 2 2 3 3 s1 1 2 2 q1 1 2 2 t1 1 a1 1 0 0 1 5 5")
    let absolute = PathData(
      "M10 10 H20 V20 L10 20 Z M15 15 C16 16 17 17 18 18 S19 19 20 20 Q21 21 22 22 T23 23 A1 1 0 0 1 28 28")
    #expect(relative.absolute() == absolute)
    // Commands before the first moveto stay as they are.
    #expect(PathData("l5 5 m1 1 l1 1").absolute() == PathData("l5 5 M1 1 L2 2"))
  }

  @Test("sums of property values stay in the ranges of the properties")
  func sumsOfPropertyValues() throws {
    let resolver = StyleResolver(style: .initial, parent: .initial, root: .initial)
    #expect(FillOpacityProperty.added(0.5, to: 0.8, in: resolver) == 1)
    #expect(OpacityProperty.added(-0.5, to: 0.2, in: resolver) == 0)
    #expect(StrokeWidthProperty.added(.pixel(-5), to: .pixel(2), in: resolver) == .pixel(0))
    #expect(StrokeMiterlimitProperty.added(-3, to: 2, in: resolver) == 1)
    #expect(StrokeDasharrayProperty.added([-5, 2], to: [1, 1], in: resolver) == [0, 3])
    // Properties whose values can't be added have no sum.
    #expect(FillRuleProperty.added(.evenodd, to: .nonzero, in: resolver) == nil)
  }

  @Test("sums and distances of paints resolve currentColor")
  func paintSumsAndDistances() throws {
    var style = ComputedStyle.initial
    style.color = try color("rgb(10, 20, 30)")
    let resolver = StyleResolver(style: style, parent: .initial, root: .initial)
    let red = Paint.color(try color("rgb(100, 0, 0)"))
    let sum = try #require(FillProperty.added(red, to: .currentColor, in: resolver))
    guard case .color(let summed) = sum else {
      Issue.record("The sum isn't a color")
      return
    }
    #expect(matches(summed, (110.0 / 255, 20.0 / 255, 30.0 / 255, 1)))
    let distance = try #require(StrokeProperty.distance(.currentColor, red, in: resolver))
    #expect(distance > 0)
    #expect(FillProperty.distance(.none, red, in: resolver) == nil)
  }
}
