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
  if case .url(id) = paint { true } else { false }
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
    #expect(!isURL(Paint.none.animated(to: .url("#a"), progress: 0.49), "#a"))
    #expect(isURL(Paint.none.animated(to: .url("#a"), progress: 0.5), "#a"))
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
    #expect(red.interpolated(to: .url("#a"), progress: 0.5) == nil)
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
}
