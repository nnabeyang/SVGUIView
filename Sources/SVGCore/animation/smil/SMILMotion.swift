import CoreGraphics
import Foundation

/// Numbers, such as the distances along a motion path, which are interpolated linearly.
private struct SMILNumberValues: SMILValueType {
  var isInterpolable: Bool { true }

  func value(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  func interpolated(_ from: Double, _ to: Double, progress: Double) -> Double {
    from + (to - from) * progress
  }

  func added(_ value: Double, to underlying: Double) -> Double? {
    underlying + value
  }

  func distance(_ from: Double, _ to: Double) -> Double? {
    abs(to - from)
  }
}

extension SMILEffect {
  /// The transform that an `<animateMotion>` adds to its element at its time, over the transform of the motions
  /// under it, or `nil` if a value of the animation is invalid, which makes the animation have no effect.
  ///
  /// The motion moves the element to a point along its path, and turns it as `rotate` says. An additive animation,
  /// and a by-animation, which SMIL makes additive, move the element from where the motions under it put it, and the
  /// other animations replace them.
  func motion(over underlying: CGAffineTransform) -> CGAffineTransform? {
    guard animation.kind == .animateMotion, let path = motionPath else { return nil }
    let measure = PathMeasure(path)
    let distance: Double
    if animation.calcMode == .paced {
      distance = min(max(state.progress, 0), 1) * measure.length
    } else if let keyPoints = animation.keyPoints {
      if let keySplines = animation.keySplines, keySplines.count != keyPoints.count - 1 { return nil }
      distance = interpolated(keyPoints, of: SMILNumberValues()) * measure.length
    } else {
      // The values are the ends of the commands of the path, which the key times and the key splines have to fit.
      let vertices = measure.vertexDistances
      if let keyTimes = animation.keyTimes, keyTimes.count != vertices.count { return nil }
      if let keySplines = animation.keySplines, keySplines.count != vertices.count - 1 { return nil }
      guard !vertices.isEmpty else { return nil }
      distance = interpolated(vertices, of: SMILNumberValues())
    }
    guard let (point, direction) = measure.point(atDistance: distance) else { return nil }
    var x = point.x
    var y = point.y
    // Each repeat starts from where the previous one ended.
    if animation.isAccumulative, state.iteration > 0, let end = measure.point(atDistance: measure.length)?.point {
      x += end.x * state.iteration
      y += end.y * state.iteration
    }
    let rotate = animation.attributes["rotate"]?.trimmingCharacters(in: .whitespaces) ?? "0"
    let angle: Double =
      switch rotate {
      case "auto": direction
      case "auto-reverse": direction + 180
      default: Double(rotate) ?? 0
      }
    let motion = CGAffineTransform(translationX: x, y: y).rotated(by: angle * .pi / 180)
    var isAdditive = animation.isAdditive
    if case .by(from: nil, by: _) = animation.values { isAdditive = true }
    return isAdditive ? motion.concatenating(underlying) : motion
  }

  /// The path that the animation moves along: the path of `<mpath>`, `path`, or the points of `values`, `from`, `to`
  /// and `by`, or `nil` without one.
  private var motionPath: PathData? {
    if let data = animation.motionPathData { return PathData(data) }
    if let data = animation.attributes["path"] { return PathData(data) }
    func point(_ text: String) -> CGPoint? {
      let numbers = text.split { $0 == "," || $0.isWhitespace }.compactMap { Double($0) }
      return numbers.count == 2 ? CGPoint(x: numbers[0], y: numbers[1]) : nil
    }
    var points = [CGPoint]()
    switch animation.values {
    case .list(let texts):
      for text in texts {
        guard let point = point(text) else { return nil }
        points.append(point)
      }
    case .to(let from, let to):
      // A to-animation starts where the element is without the motion.
      guard let end = point(to), let start = from.map(point) ?? .zero else { return nil }
      points = [start, end]
    case .by(let from, let by):
      guard let start = from.map(point) ?? .zero, let offset = point(by) else { return nil }
      points = [start, CGPoint(x: start.x + offset.x, y: start.y + offset.y)]
    case .none:
      return nil
    }
    // The points are the vertices of lines between them.
    let commands = points.enumerated().map { index, point in
      PathCommand(type: index == 0 ? .M : .L, values: [point.x, point.y])
    }
    return PathData(commands: commands)
  }
}
