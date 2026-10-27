import Foundation

/// A CSS animation that an element runs, at the time of the document.
struct ElementAnimation {
  /// The keyframes of the animation by their offsets, in the order of the offsets, and of the rule for equal ones.
  private let keyframes: [(offset: Double, keyframe: Keyframe)]
  /// The progress through the current iteration, after the direction.
  private let progress: Double
  /// Whether the animation is before its active interval, where `steps()` with a jump at the start steps back.
  private let isBefore: Bool
  /// The easing function of the intervals between keyframes that have none of their own.
  private let easing: EasingFunction

  /// The animations that the computed values of CSS Animations give, in the order of `animation-name`, without
  /// the ones that have no keyframes or no effect at the time.
  ///
  /// The other lists repeat to the length of `animation-name`, and the extra values are dropped, as CSS
  /// Animations specifies.
  static func animations(of style: ComputedStyle, in animations: DocumentAnimations) -> [ElementAnimation] {
    style.animationName.indices.compactMap { index in
      guard case .keyframes(let name) = style.animationName[index], let rule = animations.keyframes[name] else {
        return nil
      }
      let (timing, isPaused) = Self.timing(of: style, at: index)
      // A paused animation has been paused since the document was loaded, so it stays at the start.
      guard let sample = timing.sample(at: isPaused ? 0 : animations.time) else { return nil }
      let keyframes = rule.keyframes.flatMap { keyframe in keyframe.offsets.map { (offset: $0, keyframe: keyframe) } }
        .enumerated()
        .sorted { $0.element.offset == $1.element.offset ? $0.offset < $1.offset : $0.element.offset < $1.element.offset }
        .map(\.element)
      return ElementAnimation(
        keyframes: keyframes, progress: sample.progress, isBefore: sample.phase == .before,
        easing: Self.value(style.animationTimingFunction, .ease, at: index))
    }
  }

  /// The timing of the animation at an index of `animation-name`, and whether it's paused.
  static func timing(of style: ComputedStyle, at index: Int) -> (timing: AnimationTiming, isPaused: Bool) {
    let timing = AnimationTiming(
      delay: value(style.animationDelay, 0, at: index), duration: value(style.animationDuration, 0, at: index),
      iterations: value(style.animationIterationCount, .count(1), at: index),
      direction: value(style.animationDirection, .normal, at: index),
      fillMode: value(style.animationFillMode, .none, at: index))
    return (timing, value(style.animationPlayState, .running, at: index) == .paused)
  }

  /// The value of a list of `animation-*` for the index of `animation-name`, which repeats the list, or the initial
  /// value for an empty list.
  private static func value<T>(_ list: [T], _ initial: T, at index: Int) -> T {
    list.isEmpty ? initial : list[index % list.count]
  }

  /// The value of the property at the time, or `nil` if no keyframe sets it.
  ///
  /// - Parameter underlying: The value under the animation, which is the value of its keyframes at 0% and 100%
  ///   where none sets the property.
  func value<P: StyleProperty>(of _: P.Type, over underlying: P.Computed, in resolver: StyleResolver) -> P.Computed? {
    var declared = [(offset: Double, value: Declared<P.Specified>, easing: EasingFunction?)]()
    for (offset, keyframe) in keyframes {
      guard let value = keyframe.declarations[P.self] else { continue }
      // Of keyframes with the same offset, the later one sets the property.
      if declared.last?.offset == offset { declared.removeLast() }
      declared.append((offset, value, keyframe.easing))
    }
    guard !declared.isEmpty else { return nil }
    var points = declared.map { (offset: $0.offset, value: resolver.computed($0.value, of: P.self), easing: $0.easing) }
    if points[0].offset > 0 { points.insert((0, underlying, nil), at: 0) }
    if points[points.count - 1].offset < 1 { points.append((1, underlying, nil)) }
    // The interval that the progress is in. A progress outside 0 to 1 uses the first or the last interval.
    var index = 0
    while index + 2 < points.count, points[index + 1].offset <= progress {
      index += 1
    }
    let from = points[index]
    let to = points[index + 1]
    let length = to.offset - from.offset
    let intervalProgress = length == 0 ? 1 : (progress - from.offset) / length
    let eased = (from.easing ?? easing)(intervalProgress, before: isBefore)
    return P.interpolated(from.value, to.value, progress: eased, in: resolver)
  }
}
