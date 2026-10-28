import Foundation

/// The timing of an animation in the terms of Web Animations, which gives its progress at each local time.
///
/// The local time comes from how the animation plays on the timeline, which ``AnimationPlayback`` describes.
struct AnimationTiming: Sendable, Equatable {
  /// The time in seconds from the start to the first iteration, which is negative to start partway through.
  var delay: Double
  /// The duration of one iteration in seconds, which isn't negative.
  var duration: Double
  var iterations: AnimationIterationCount
  /// Where in the iterations the animation starts, such as 0.5 to start halfway through the first one.
  var iterationStart: Double = 0
  var direction: AnimationDirection
  var fillMode: AnimationFillMode
  /// The easing function of the whole iteration. CSS Animations keep it linear, since their easing functions
  /// apply to each interval between keyframes instead.
  var easing: EasingFunction = .linear

  /// The duration of all the iterations, which is infinite for an infinite count of iterations that take time.
  var activeDuration: Double {
    switch iterations {
    case .count(let count): duration == 0 || count == 0 ? 0 : duration * count
    case .infinite: duration == 0 ? 0 : .infinity
    }
  }

  /// The local time of the end of the active interval, after the delay.
  var end: Double {
    delay + activeDuration
  }

  /// The iterations as a number, which is infinite for an infinite count.
  private var iterationCount: Double {
    switch iterations {
    case .count(let count): count
    case .infinite: .infinity
    }
  }

  /// The animation's phase, iteration and progress at the given local time, or `nil` if the animation has no
  /// effect then, which is before it starts or after it ends without filling.
  func sample(at localTime: Double) -> AnimationSample? {
    let activeDuration = activeDuration
    let endTime = max(delay + activeDuration, 0)
    let phase: AnimationPhase =
      if localTime < max(min(delay, endTime), 0) {
        .before
      } else if localTime >= max(min(delay + activeDuration, endTime), 0) {
        .after
      } else {
        .active
      }
    let activeTime: Double
    switch phase {
    case .before:
      guard fillMode == .backwards || fillMode == .both else { return nil }
      activeTime = max(localTime - delay, 0)
    case .active:
      activeTime = localTime - delay
    case .after:
      guard fillMode == .forwards || fillMode == .both else { return nil }
      activeTime = max(min(localTime - delay, activeDuration), 0)
    }
    let overallProgress =
      if duration == 0 {
        phase == .before ? iterationStart : iterationStart + iterationCount
      } else {
        activeTime / duration + iterationStart
      }
    var simpleProgress =
      overallProgress.isInfinite
      ? iterationStart.truncatingRemainder(dividingBy: 1) : overallProgress.truncatingRemainder(dividingBy: 1)
    // The end of an iteration is its progress 1, not the start of the next iteration.
    if simpleProgress == 0, phase != .before, activeTime == activeDuration, iterationCount != 0,
      overallProgress != 0
    {
      simpleProgress = 1
    }
    let iteration: Double =
      if phase == .after, iterationCount.isInfinite {
        .infinity
      } else if simpleProgress == 1 {
        overallProgress.rounded(.down) - 1
      } else {
        overallProgress.rounded(.down)
      }
    let isForwards =
      switch direction {
      case .normal: true
      case .reverse: false
      case .alternate: Self.isEven(iteration)
      case .alternateReverse: Self.isEven(iteration + 1)
      }
    let directedProgress = isForwards ? simpleProgress : 1 - simpleProgress
    return AnimationSample(
      phase: phase, iteration: iteration, progress: easing(directedProgress, before: phase == .before))
  }

  /// Whether an iteration runs forwards when the animation alternates. An infinite iteration runs forwards.
  private static func isEven(_ iteration: Double) -> Bool {
    iteration.isInfinite || iteration.truncatingRemainder(dividingBy: 2) == 0
  }
}

/// Where an animation is in time relative to its active interval.
enum AnimationPhase: Sendable, Equatable {
  case before
  case active
  case after
}

/// The state of an animation at a time.
struct AnimationSample: Sendable, Equatable {
  let phase: AnimationPhase
  /// The index of the current iteration, starting at 0, which can be infinite after an infinite animation.
  let iteration: Double
  /// The progress through the current iteration after the direction and the easing function, usually between 0
  /// and 1.
  let progress: Double
}
