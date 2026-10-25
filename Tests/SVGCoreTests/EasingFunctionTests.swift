import Foundation
import Testing

@testable import SVGCore

/// Whether two numbers are equal, apart from the error of solving the curve.
private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool {
  abs(a - b) < tolerance
}

@Suite("Easing functions")
struct EasingFunctionTests {
  @Test("the keywords start at 0 and end at 1", arguments: [EasingFunction.ease, .easeIn, .easeOut, .easeInOut])
  func ends(easing: EasingFunction) {
    #expect(isClose(easing(0), 0))
    #expect(isClose(easing(1), 1))
  }

  @Test("cubic Bézier curves give the output at the point of the curve whose x is the input")
  func cubicBezierValues() {
    #expect(isClose(EasingFunction.ease(0.5), 0.8024033877, tolerance: 1e-6))
    #expect(isClose(EasingFunction.easeInOut(0.5), 0.5))
    #expect(isClose(EasingFunction.cubicBezier(x1: 0, y1: 0, x2: 1, y2: 1)(0.3), 0.3))
    // ease-in and ease-out are the same curve turned around.
    for input in stride(from: 0.0, through: 1, by: 0.05) {
      #expect(isClose(EasingFunction.easeIn(input) + EasingFunction.easeOut(1 - input), 1), "at \(input)")
    }
  }

  @Test("cubic Bézier curves with a flat end find the parameter by bisection")
  func cubicBezierFlatEnd() {
    let easing = EasingFunction.cubicBezier(x1: 1, y1: 0, x2: 1, y2: 0)
    var last = -Double.infinity
    for input in stride(from: 0.0, through: 1, by: 0.01) {
      let output = easing(input)
      #expect(output >= last - 1e-9, "at \(input)")
      last = output
    }
    #expect(isClose(easing(1), 1))
  }

  @Test(
    "cubic Bézier curves continue along the tangent at the ends",
    arguments: [
      (EasingFunction.cubicBezier(x1: 0.5, y1: 1, x2: 0.5, y2: 1), -1.0, -2.0),
      (.cubicBezier(x1: 0, y1: 0, x2: 0.5, y2: 1), -1, -2),
      (.cubicBezier(x1: 0, y1: 0.5, x2: 0, y2: 0.5), -1, 0),
      (.cubicBezier(x1: 0.5, y1: 0, x2: 0.5, y2: 0), 2, 3),
      (.cubicBezier(x1: 0.5, y1: 0, x2: 1, y2: 0.5), 2, 3),
      (.cubicBezier(x1: 1, y1: 0.5, x2: 1, y2: 0.5), 2, 1),
    ])
  func cubicBezierOutside(easing: EasingFunction, input: Double, output: Double) {
    #expect(isClose(easing(input), output))
  }

  /// The outputs of `steps(3, …)` at some inputs, for each position.
  private static let threeSteps: [(EasingFunction.StepPosition, [(Double, Double)])] = [
    (.jumpEnd, [(0.0, 0.0), (0.33, 0), (0.34, 1.0 / 3), (0.99, 2.0 / 3), (1, 1)]),
    (.jumpStart, [(0, 1.0 / 3), (0.33, 1.0 / 3), (0.34, 2.0 / 3), (0.67, 1), (1, 1)]),
    (.jumpNone, [(0, 0), (0.33, 0), (0.34, 0.5), (0.67, 1), (1, 1)]),
    (.jumpBoth, [(0, 0.25), (0.33, 0.25), (0.34, 0.5), (0.67, 0.75), (1, 1)]),
  ]

  @Test("steps() jump where their positions say", arguments: threeSteps)
  func steps(position: EasingFunction.StepPosition, values: [(Double, Double)]) {
    for (input, output) in values {
      #expect(isClose(EasingFunction.steps(3, position)(input), output), "\(position) at \(input)")
    }
  }

  @Test("steps() don't jump at the input of a jump before the active interval")
  func stepsBefore() {
    #expect(EasingFunction.steps(1, .jumpStart)(0, before: true) == 0)
    #expect(EasingFunction.steps(1, .jumpStart)(0) == 1)
    #expect(EasingFunction.steps(2, .jumpBoth)(0, before: true) == 0)
    #expect(EasingFunction.steps(1, .jumpEnd)(0, before: true) == 0)
  }

  @Test(
    "linear() interpolates between its points and continues the lines at its ends",
    arguments: [(-0.5, -0.8), (0.0, 0.0), (0.25, 0.4), (0.5, 0.8), (0.75, 0.9), (1, 1), (1.5, 1.2)])
  func piecewiseLinear(input: Double, output: Double) throws {
    let easing = try #require(EasingFunction.piecewiseLinear(stops: [(0, nil), (0.8, 0.5), (1, nil)]))
    #expect(isClose(easing(input), output))
  }

  @Test("linear() jumps at two points with the same input")
  func piecewiseLinearJump() throws {
    let easing = try #require(EasingFunction.piecewiseLinear(stops: [(0, nil), (0, 0.5), (1, 0.5), (1, nil)]))
    #expect(isClose(easing(0.25), 0))
    #expect(isClose(easing(0.5), 1))
    #expect(isClose(easing(0.75), 1))
  }
}
