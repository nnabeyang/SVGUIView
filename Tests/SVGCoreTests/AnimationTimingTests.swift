import Foundation
import Testing

@testable import SVGCore

private func timing(
  delay: Double = 0, duration: Double = 1, iterations: AnimationIterationCount = .count(1),
  iterationStart: Double = 0, direction: AnimationDirection = .normal, fillMode: AnimationFillMode = .none,
  easing: EasingFunction = .linear
) -> AnimationTiming {
  AnimationTiming(
    delay: delay, duration: duration, iterations: iterations, iterationStart: iterationStart, direction: direction,
    fillMode: fillMode, easing: easing)
}

/// Whether the sample has the phase, iteration and progress, apart from the error of the arithmetic.
private func matches(_ sample: AnimationSample?, _ phase: AnimationPhase, _ iteration: Double, _ progress: Double)
  -> Bool
{
  guard let sample else { return false }
  return sample.phase == phase && sample.iteration == iteration && abs(sample.progress - progress) < 1e-9
}

@Suite("Animation timing")
struct AnimationTimingTests {
  @Test("an animation has no effect outside its active interval without filling")
  func activeInterval() {
    let timing = timing(delay: 1, duration: 2)
    #expect(timing.sample(at: 0.999) == nil)
    #expect(matches(timing.sample(at: 1), .active, 0, 0))
    #expect(matches(timing.sample(at: 2), .active, 0, 0.5))
    #expect(matches(timing.sample(at: 2.999), .active, 0, 0.9995))
    #expect(timing.sample(at: 3) == nil)
  }

  @Test("a negative delay starts partway through")
  func negativeDelay() {
    let timing = timing(delay: -1, duration: 2)
    #expect(matches(timing.sample(at: 0), .active, 0, 0.5))
    #expect(timing.sample(at: 1) == nil)
  }

  @Test(
    "fill modes keep the start before the animation and the end after it",
    arguments: [
      (AnimationFillMode.none, false, false), (.forwards, false, true), (.backwards, true, false), (.both, true, true),
    ])
  func fillModes(fillMode: AnimationFillMode, fillsBefore: Bool, fillsAfter: Bool) {
    let timing = timing(delay: 1, duration: 2, fillMode: fillMode)
    let before = timing.sample(at: 0)
    let after = timing.sample(at: 5)
    #expect(fillsBefore ? matches(before, .before, 0, 0) : before == nil)
    #expect(fillsAfter ? matches(after, .after, 0, 1) : after == nil)
  }

  @Test("the end of an iteration is its progress 1, and the next iteration starts at 0")
  func iterationBoundaries() {
    let timing = timing(iterations: .count(2), fillMode: .forwards)
    #expect(matches(timing.sample(at: 0.999), .active, 0, 0.999))
    #expect(matches(timing.sample(at: 1), .active, 1, 0))
    #expect(matches(timing.sample(at: 2), .after, 1, 1))
  }

  @Test("an animation with a fraction of an iteration ends partway through its last iteration")
  func fractionalIterations() {
    let timing = timing(iterations: .count(2.5), fillMode: .forwards)
    #expect(matches(timing.sample(at: 10), .after, 2, 0.5))
  }

  @Test("an infinite animation keeps repeating")
  func infiniteIterations() {
    let timing = timing(iterations: .infinite)
    #expect(matches(timing.sample(at: 100.25), .active, 100, 0.25))
  }

  @Test(
    "directions decide which way each iteration runs",
    arguments: [
      (AnimationDirection.normal, 0.25, 0.25), (.reverse, 0.75, 0.75), (.alternate, 0.25, 0.75),
      (.alternateReverse, 0.75, 0.25),
    ])
  func directions(direction: AnimationDirection, first: Double, second: Double) {
    let timing = timing(iterations: .count(2), direction: direction)
    #expect(matches(timing.sample(at: 0.25), .active, 0, first))
    #expect(matches(timing.sample(at: 1.25), .active, 1, second))
  }

  @Test("an animation without a duration jumps from its start to its end")
  func zeroDuration() {
    let timing = timing(delay: 1, duration: 0, iterations: .count(2), fillMode: .both)
    #expect(matches(timing.sample(at: 0), .before, 0, 0))
    #expect(matches(timing.sample(at: 1), .after, 1, 1))
  }

  @Test("an animation without iterations stays at its start")
  func zeroIterations() {
    let timing = timing(iterations: .count(0), fillMode: .both)
    #expect(matches(timing.sample(at: 0), .after, 0, 0))
    #expect(matches(timing.sample(at: 5), .after, 0, 0))
  }

  @Test("an iteration start moves where the iterations start")
  func iterationStart() {
    let timing = timing(iterationStart: 0.5, fillMode: .forwards)
    #expect(matches(timing.sample(at: 0), .active, 0, 0.5))
    #expect(matches(timing.sample(at: 0.5), .active, 1, 0))
    #expect(matches(timing.sample(at: 1), .after, 1, 0.5))
  }

  @Test("the easing function of the iteration gets the before flag")
  func easing() {
    let timing = timing(delay: 1, fillMode: .backwards, easing: .steps(1, .jumpStart))
    #expect(matches(timing.sample(at: 0.5), .before, 0, 0))
    #expect(matches(timing.sample(at: 1), .active, 0, 1))
  }
}
