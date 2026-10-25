import Foundation

/// A function that maps the progress of an animation to the progress of its value, as in CSS Easing Functions.
///
/// It isn't specific to CSS: SMIL animations use the same functions for `calcMode` and `keySplines`.
enum EasingFunction: Sendable, Equatable {
  /// The identity, `linear`.
  case linear
  /// `linear()` with its control points, whose inputs are filled in and never decrease.
  case piecewiseLinear([LinearPoint])
  /// `cubic-bezier()`, with `x1` and `x2` between 0 and 1.
  case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)
  /// `steps()`, with at least one step, or two for ``StepPosition/jumpNone``.
  case steps(Int, StepPosition)

  static let ease = EasingFunction.cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
  static let easeIn = EasingFunction.cubicBezier(x1: 0.42, y1: 0, x2: 1, y2: 1)
  static let easeOut = EasingFunction.cubicBezier(x1: 0, y1: 0, x2: 0.58, y2: 1)
  static let easeInOut = EasingFunction.cubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

  /// A control point of `linear()`.
  struct LinearPoint: Sendable, Equatable {
    let input: Double
    let output: Double
  }

  /// Where the jumps of `steps()` are.
  enum StepPosition: Sendable, Equatable {
    case jumpStart
    case jumpEnd
    case jumpNone
    case jumpBoth
  }

  /// The function of `linear()` with the given stops, whose inputs are filled in as CSS Easing Functions
  /// specifies, or `nil` if there are fewer than two points.
  ///
  /// - Parameter stops: The output of each point, and its input if it has one.
  static func piecewiseLinear(stops: [(output: Double, input: Double?)]) -> EasingFunction? {
    guard stops.count >= 2 else { return nil }
    var inputs = stops.map(\.input)
    if inputs[0] == nil { inputs[0] = 0 }
    if inputs[inputs.count - 1] == nil { inputs[inputs.count - 1] = 1 }
    // An input less than one before it becomes the largest one before it.
    var largest = -Double.infinity
    for index in inputs.indices {
      guard let input = inputs[index] else { continue }
      largest = max(largest, input)
      inputs[index] = largest
    }
    // Points without an input are spread evenly between the points around them.
    var index = 0
    while index < inputs.count {
      guard inputs[index] == nil else {
        index += 1
        continue
      }
      let start = index - 1
      var end = index
      while inputs[end] == nil { end += 1 }
      let (from, to) = (inputs[start]!, inputs[end]!)
      for missing in index..<end {
        inputs[missing] = from + (to - from) * Double(missing - start) / Double(end - start)
      }
      index = end
    }
    return .piecewiseLinear(zip(stops, inputs).map { LinearPoint(input: $1!, output: $0.output) })
  }
}
