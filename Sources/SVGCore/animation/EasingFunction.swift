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

extension EasingFunction {
  /// The output progress for the input progress, as CSS Easing Functions defines it for each function.
  ///
  /// - Parameter before: The before flag, which is set while the animation is before its active interval. Only
  ///   `steps()` uses it.
  func callAsFunction(_ input: Double, before: Bool = false) -> Double {
    switch self {
    case .linear:
      input
    case .piecewiseLinear(let points):
      Self.piecewiseLinear(points, input)
    case .cubicBezier(let x1, let y1, let x2, let y2):
      Self.cubicBezier(x1: x1, y1: y1, x2: x2, y2: y2, input)
    case .steps(let count, let position):
      Self.steps(count, position, input, before: before)
    }
  }

  private static func piecewiseLinear(_ points: [LinearPoint], _ input: Double) -> Double {
    // The last point whose input isn't greater, or the first point, and the point after it. An input outside the
    // points continues the line of the two points at that end.
    var index = points.lastIndex { $0.input <= input } ?? 0
    if index == points.count - 1 { index -= 1 }
    let (a, b) = (points[index], points[index + 1])
    if a.input == b.input { return b.output }
    return a.output + (input - a.input) / (b.input - a.input) * (b.output - a.output)
  }

  private static func cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double, _ input: Double) -> Double {
    // Outside 0...1, the output continues along the tangent at the end.
    if input < 0 {
      if x1 > 0 { return y1 / x1 * input }
      if x2 > 0 { return y2 / x2 * input }
      return 0
    }
    if input > 1 {
      if x2 < 1 { return 1 + (y2 - 1) / (x2 - 1) * (input - 1) }
      if x1 < 1 { return 1 + (y1 - 1) / (x1 - 1) * (input - 1) }
      return 1
    }
    // The curve from (0, 0) to (1, 1) as polynomials of the parameter t.
    func polynomial(_ p1: Double, _ p2: Double) -> (a: Double, b: Double, c: Double) {
      let c = 3 * p1
      let b = 3 * (p2 - p1) - c
      return (1 - c - b, b, c)
    }
    let x = polynomial(x1, x2)
    let y = polynomial(y1, y2)
    func value(_ p: (a: Double, b: Double, c: Double), _ t: Double) -> Double {
      ((p.a * t + p.b) * t + p.c) * t
    }
    // The parameter whose x is the input: Newton's method, then bisection if it doesn't converge, since x
    // increases with t when x1 and x2 are between 0 and 1.
    let epsilon = 1e-9
    var t = input
    for _ in 0..<8 {
      let error = value(x, t) - input
      if abs(error) < epsilon { return value(y, t) }
      let slope = (3 * x.a * t + 2 * x.b) * t + x.c
      if abs(slope) < 1e-6 { break }
      t -= error / slope
    }
    var (low, high) = (0.0, 1.0)
    t = input
    while low < high {
      let current = value(x, t)
      if abs(current - input) < epsilon { break }
      if current < input { low = t } else { high = t }
      let next = (low + high) / 2
      if next == t { break }
      t = next
    }
    return value(y, t)
  }

  private static func steps(_ count: Int, _ position: StepPosition, _ input: Double, before: Bool) -> Double {
    let steps = Double(count)
    var step = (input * steps).rounded(.down)
    if position == .jumpStart || position == .jumpBoth { step += 1 }
    // Just before the active interval, a step that jumps at the input doesn't jump yet.
    if before, (input * steps).truncatingRemainder(dividingBy: 1) == 0 { step -= 1 }
    if input >= 0, step < 0 { step = 0 }
    let jumps: Double =
      switch position {
      case .jumpStart, .jumpEnd: steps
      case .jumpNone: steps - 1
      case .jumpBoth: steps + 1
      }
    if input <= 1, step > jumps { step = jumps }
    return step / jumps
  }
}
