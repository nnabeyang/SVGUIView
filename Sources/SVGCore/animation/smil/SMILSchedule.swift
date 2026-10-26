import Foundation

/// An interval in which a SMIL animation is active.
struct SMILInterval: Sendable, Equatable {
  /// The time in seconds that the interval begins at.
  let begin: Double
  /// The time in seconds that the interval ends at, which is infinite for an interval that doesn't end.
  let end: Double
  /// The time in seconds that the animation stops playing its simple duration at, from which it fills as `fill`
  /// says. It's before the end when `min` makes the active duration longer than the repeats of the simple duration.
  let playEnd: Double
}

/// The intervals of the SMIL animations of a document, up to a time.
///
/// The intervals follow SMIL 3.0: the begin and end values of an animation give its interval times, and its
/// duration, repeats, `min`, `max` and `restart` give the intervals. Syncbase values, such as `a.end+1s`, take the
/// times from the intervals of the other animation.
struct SMILSchedule: Sendable {
  private let animations: [SMILAnimation]
  /// The intervals of each animation, in the order of `animations`.
  private(set) var intervals: [[SMILInterval]]

  /// The most times that the intervals are found again with the times of the syncbase values. Each time can add an
  /// interval to an animation that depends on itself through other animations, so the limit stops a cycle of very
  /// short intervals.
  private static let maximumPasses = 1000
  /// The most intervals of one animation.
  private static let maximumIntervals = 1000

  /// The intervals of animations that begin at the time or before it.
  ///
  /// - Parameter time: The time in seconds since the document began.
  init(animations: [SMILAnimation], until time: Double) {
    self.animations = animations
    // Of animations with the same ID, the first one in the document is the one that syncbase values find.
    var indices = [String: Int]()
    for (index, animation) in animations.enumerated() {
      if let id = animation.id, indices[id] == nil {
        indices[id] = index
      }
    }
    var intervals = animations.map { _ in [SMILInterval]() }
    for _ in 0..<Self.maximumPasses {
      let next = animations.map { animation in
        Self.intervals(
          of: animation, begins: Self.times(of: animation.begin, indices: indices, intervals: intervals),
          ends: animation.end.map { Self.times(of: $0, indices: indices, intervals: intervals) }, until: time)
      }
      if next == intervals { break }
      intervals = next
    }
    self.intervals = intervals
  }

  /// The times of a `begin` or `end` list, in order, with the times of syncbase values from the intervals found so
  /// far. Values that don't resolve, such as `indefinite`, give no time.
  private static func times(
    of values: [SMILTimeValue], indices: [String: Int], intervals: [[SMILInterval]]
  ) -> [Double] {
    var times = [Double]()
    for value in values {
      switch value {
      case .offset(let offset):
        times.append(offset)
      case .syncbase(let id, let event, let offset):
        guard let index = indices[id] else { continue }
        for interval in intervals[index] {
          let time = event == .begin ? interval.begin : interval.end
          if time.isFinite { times.append(time + offset) }
        }
      case .indefinite, .unresolved:
        break
      }
    }
    return times.sorted()
  }

  /// The intervals of an animation that begin at the time or before it.
  ///
  /// - Parameters:
  ///   - begins: The begin times in order.
  ///   - ends: The end times in order, or `nil` if the animation has no `end` attribute.
  private static func intervals(
    of animation: SMILAnimation, begins: [Double], ends: [Double]?, until time: Double
  ) -> [SMILInterval] {
    // An `end` list with values that can resolve later, such as `indefinite` or a syncbase value, doesn't stop the
    // intervals when none of its times is after a begin.
    let endsCanResolveLater =
      animation.end?.contains {
        if case .offset = $0 { false } else { true }
      } ?? false
    var intervals = [SMILInterval]()
    var beginAfter = -Double.infinity
    var previousBegin = -Double.infinity
    while intervals.count < maximumIntervals {
      guard let begin = begins.first(where: { $0 >= beginAfter && $0 > previousBegin }), begin <= time else {
        break
      }
      var end: Double?
      if let ends {
        if let time = ends.first(where: { $0 >= begin }) {
          end = time
        } else if endsCanResolveLater {
          end = .infinity
        } else {
          break
        }
      }
      let (active, played) = activeDuration(of: animation, from: begin, to: end)
      var intervalEnd = begin + active
      // With `restart="always"`, a begin time in the interval ends it and begins the next one.
      if animation.restart == .always, let restart = begins.first(where: { $0 > begin && $0 < intervalEnd }) {
        intervalEnd = restart
      }
      let playEnd = min(begin + played, intervalEnd)
      previousBegin = begin
      beginAfter = intervalEnd
      // The first interval is the first one that doesn't end before the document begins.
      if intervals.isEmpty, intervalEnd < 0 { continue }
      intervals.append(SMILInterval(begin: begin, end: intervalEnd, playEnd: playEnd))
      if animation.restart == .never || intervalEnd.isInfinite { break }
    }
    return intervals
  }

  /// The active duration of an interval, and how long of it the animation plays its simple duration before it fills,
  /// in seconds, which are infinite for an indefinite duration.
  ///
  /// - Parameter end: The end time of the interval from the `end` list, or `nil` if the animation has none.
  static func activeDuration(
    of animation: SMILAnimation, from begin: Double, to end: Double?
  ) -> (active: Double, played: Double) {
    let simple = animation.duration ?? .infinity
    let repeated: Double? =
      switch animation.repeatCount {
      case .count(let count): simple * count
      case .infinite: .infinity
      case nil: nil
      }
    let intermediate: Double =
      switch (repeated, animation.repeatDuration) {
      case (nil, nil): simple
      case (let repeated?, nil): repeated
      case (nil, let duration?): duration
      case (let repeated?, let duration?): min(repeated, duration)
      }
    let preliminary = end.map { min(intermediate, $0 - begin) } ?? intermediate
    let active = min(animation.maximum, max(animation.minimum, preliminary))
    // When `min` makes the active duration longer, the animation plays its repeats and then fills.
    return (active, min(intermediate, active))
  }
}
