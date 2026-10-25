import Foundation

/// A type whose values can be animated: interpolated between two values, added and measured.
protocol Animatable: Sendable {
  /// The value at `progress` between `self` and `other`, or `nil` when the two values can't be interpolated and
  /// the animation falls back to a discrete step. The progress can be outside 0 to 1, since easing functions can
  /// overshoot.
  func interpolated(to other: Self, progress: Double) -> Self?
  /// The sum used by additive and accumulating animations, or `nil` when the two values can't be added.
  func adding(_ other: Self) -> Self?
  /// The distance used by paced animations, or `nil` when the two values can't be measured.
  func pacedDistance(to other: Self) -> Double?
}

extension Animatable {
  /// The value at `progress` between `self` and `other`, which steps from `self` to `other` halfway when the two
  /// values can't be interpolated.
  func animated(to other: Self, progress: Double) -> Self {
    interpolated(to: other, progress: progress) ?? discrete(self, other, progress: progress)
  }
}

/// The value of a discrete animation from `from` to `to`, which steps halfway.
func discrete<Value>(_ from: Value, _ to: Value, progress: Double) -> Value {
  progress < 0.5 ? from : to
}

extension Double: Animatable {
  func interpolated(to other: Double, progress: Double) -> Double? {
    self + (other - self) * progress
  }

  func adding(_ other: Double) -> Double? {
    self + other
  }

  func pacedDistance(to other: Double) -> Double? {
    abs(other - self)
  }
}

extension CGFloat: Animatable {
  func interpolated(to other: CGFloat, progress: Double) -> CGFloat? {
    self + (other - self) * progress
  }

  func adding(_ other: CGFloat) -> CGFloat? {
    self + other
  }

  func pacedDistance(to other: CGFloat) -> Double? {
    Double(abs(other - self))
  }
}

/// A value that may be missing, such as `auto`, which is animated only when both values are there.
extension Optional: Animatable where Wrapped: Animatable {
  func interpolated(to other: Wrapped?, progress: Double) -> Wrapped?? {
    guard let self, let other, let value = self.interpolated(to: other, progress: progress) else { return nil }
    return .some(value)
  }

  func adding(_ other: Wrapped?) -> Wrapped?? {
    guard let self, let other, let value = self.adding(other) else { return nil }
    return .some(value)
  }

  func pacedDistance(to other: Wrapped?) -> Double? {
    guard let self, let other else { return nil }
    return self.pacedDistance(to: other)
  }
}

/// `visibility` steps as a discrete value, except that it stays `visible` between `visible` and another value.
extension CSSVisibility: Animatable {
  func interpolated(to other: CSSVisibility, progress: Double) -> CSSVisibility? {
    guard self != other, self == .visible || other == .visible else { return nil }
    return if progress <= 0 {
      self
    } else if progress >= 1 {
      other
    } else {
      .visible
    }
  }

  func adding(_: CSSVisibility) -> CSSVisibility? {
    nil
  }

  func pacedDistance(to _: CSSVisibility) -> Double? {
    nil
  }
}
