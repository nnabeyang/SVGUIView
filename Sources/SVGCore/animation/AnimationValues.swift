import Foundation

// The timing values of an animation, in the terms of Web Animations. CSS Animations and SMIL animations both
// translate into them.

/// How many times an animation repeats.
enum AnimationIterationCount: Sendable, Equatable {
  /// A count that isn't negative, which can have a fraction.
  case count(Double)
  case infinite
}

/// Which way each iteration of an animation runs.
enum AnimationDirection: String, CaseIterable, Sendable {
  case normal
  case reverse
  case alternate
  case alternateReverse = "alternate-reverse"
}

/// Whether an animation applies its values before it starts and after it ends.
enum AnimationFillMode: String, CaseIterable, Sendable {
  case none
  case forwards
  case backwards
  case both
}

/// Whether an animation runs or is paused.
enum AnimationPlayState: String, CaseIterable, Sendable {
  case running
  case paused
}
