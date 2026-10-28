import Foundation

/// The identity of a CSS animation: the element that runs it, and a name of its `animation-name` with the number of
/// the same names before it, so that adding or removing other names keeps the identity.
package struct CSSAnimationID: Hashable, Sendable {
  package let element: ElementID
  package let name: String
  package let occurrence: Int
}

/// How a CSS animation plays on the timeline of its document, in the terms of Web Animations: the local time that
/// it's at, which advances with the time of the timeline at its playback rate, or which is held while it's paused.
package struct AnimationPlayback: Equatable, Sendable {
  /// A time of the timeline in seconds, and the local time that the animation was at then.
  private var anchor: (time: Double, localTime: Double)
  /// The local time of a paused animation, or `nil` for one that plays.
  private var holdTime: Double?
  /// How fast the local time advances with the time of the timeline, which is negative to play backward.
  package private(set) var rate: Double

  /// The playback of an animation that started at a time of the timeline, or that is paused at its start.
  package init(startTime: Double = 0, isPaused: Bool = false) {
    anchor = (startTime, 0)
    holdTime = isPaused ? 0 : nil
    rate = 1
  }

  package static func == (lhs: AnimationPlayback, rhs: AnimationPlayback) -> Bool {
    lhs.anchor == rhs.anchor && lhs.holdTime == rhs.holdTime && lhs.rate == rhs.rate
  }

  package var isPaused: Bool {
    holdTime != nil
  }

  /// The local time of the animation at a time of the timeline, in seconds.
  package func localTime(at time: Double) -> Double {
    holdTime ?? anchor.localTime + (time - anchor.time) * rate
  }

  /// Holds the local time that the animation is at.
  package mutating func pause(at time: Double) {
    guard holdTime == nil else { return }
    holdTime = localTime(at: time)
  }

  /// Plays the animation from the local time that it's held at.
  package mutating func play(at time: Double) {
    guard let holdTime else { return }
    anchor = (time, holdTime)
    self.holdTime = nil
  }

  /// Moves the animation to a local time, which a paused animation holds.
  package mutating func seek(to localTime: Double, at time: Double) {
    if holdTime != nil {
      holdTime = localTime
    } else {
      anchor = (time, localTime)
    }
  }

  /// Changes the playback rate from the local time that the animation is at.
  package mutating func setRate(_ rate: Double, at time: Double) {
    if holdTime == nil {
      anchor = (time, localTime(at: time))
    }
    self.rate = rate
  }

  /// Whether a playing animation has reached the end of its active interval, or its start when it plays backward,
  /// as Web Animations' finished play state is.
  ///
  /// - Parameter end: The local time of the end of the active interval, after the delay.
  package func isFinished(at time: Double, end: Double) -> Bool {
    guard holdTime == nil else { return false }
    let localTime = localTime(at: time)
    return rate > 0 && localTime >= end || rate < 0 && localTime <= 0
  }

  /// The time of the timeline at which a playing animation reaches the end of its active interval, or its start
  /// when it plays backward, after which it doesn't change, or `nil` if it never changes from now on.
  ///
  /// - Parameter end: The local time of the end of the active interval, after the delay.
  func timeOfFinish(end: Double) -> Double? {
    guard holdTime == nil, rate != 0 else { return nil }
    return anchor.time + ((rate > 0 ? end : 0) - anchor.localTime) / rate
  }
}

extension DocumentAnimations {
  /// The playback of a CSS animation, which is the one that the document keeps for it, or for an animation that it
  /// keeps none for, one that started as the document was loaded, or that is paused at its start.
  func playback(of id: CSSAnimationID, isPaused: Bool) -> AnimationPlayback {
    playback[id] ?? AnimationPlayback(isPaused: isPaused)
  }
}

extension ComputedStyle {
  /// The CSS animations that an element runs with these values, in the order of `animation-name`: each name with the
  /// number of the same names before it and its index, without the names that the document has no keyframes for.
  func cssAnimations(keyframes: [String: KeyframesRule]) -> [(name: String, occurrence: Int, index: Int)] {
    var counts = [String: Int]()
    return animationName.indices.compactMap { index in
      guard case .keyframes(let name) = animationName[index], keyframes[name] != nil else { return nil }
      let occurrence = counts[name, default: 0]
      counts[name] = occurrence + 1
      return (name, occurrence, index)
    }
  }
}

extension SVGBaseContext {
  /// The CSS animations that the elements run, in document order and in the order of each element's
  /// `animation-name`, without the names that the document has no keyframes for.
  package func cssAnimations() -> [CSSAnimationID] {
    (root?.elements ?? []).flatMap { element in
      element.style.cssAnimations(keyframes: animations.keyframes).map {
        CSSAnimationID(element: element.base.elementID, name: $0.name, occurrence: $0.occurrence)
      }
    }
  }

  /// The playback of a CSS animation, or `nil` if no element runs it.
  package func playback(of id: CSSAnimationID) -> AnimationPlayback? {
    timing(of: id).map { animations.playback(of: id, isPaused: $0.isPaused) }
  }

  /// Whether a CSS animation has finished at a time of the timeline, or no element runs it.
  package func isFinished(_ id: CSSAnimationID, at time: Double) -> Bool {
    guard let (timing, isPaused) = timing(of: id) else { return true }
    return animations.playback(of: id, isPaused: isPaused).isFinished(at: time, end: timing.end)
  }

  /// The timing of a CSS animation and whether `animation-play-state` pauses it, or `nil` if no element runs it.
  private func timing(of id: CSSAnimationID) -> (timing: AnimationTiming, isPaused: Bool)? {
    guard let element = root?.elements.first(where: { $0.base.elementID == id.element }),
      let animation = element.style.cssAnimations(keyframes: animations.keyframes).first(where: {
        $0.name == id.name && $0.occurrence == id.occurrence
      })
    else { return nil }
    return ElementAnimation.timing(of: element.style, at: animation.index)
  }
}
