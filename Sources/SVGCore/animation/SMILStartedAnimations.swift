import Foundation

/// The CSS animations that SMIL animations apply, by changing `class`, `style` or other attributes that the selectors
/// or the declarations of the style sheets match.
///
/// A CSS animation starts when an element starts running it, so one that a SMIL animation applies starts at the time
/// that the SMIL animation changes the attribute, and starts again when it's applied again after it stopped.
struct SMILStartedAnimations: Sendable, Equatable {
  /// The times in seconds that the elements start running the animations, in order, after the time that the
  /// document was loaded, for the animations that the SMIL animations apply.
  var starts = [CSSAnimationID: [Double]]()
  /// The time in seconds after which the animations that the SMIL animations apply don't change, which is infinite
  /// when the times that they apply them can't all be found.
  var end = 0.0

  /// No animations that SMIL animations apply.
  init() {}

  /// The most times at which the attributes that SMIL animations change are checked, each of which finds the SMIL
  /// effects at the time.
  private static let maximumTimes = 2000

  /// The animations that the SMIL animations of a document apply.
  ///
  /// The attributes can change only at the times that the intervals of the SMIL animations that change them begin
  /// and end, and that their values change in between. At each time that they change, the elements are made with
  /// them, and the animations that the elements run then and didn't run before start then.
  ///
  /// - Parameter passes: The most passes of the schedule of the SMIL animations, as their end is found with.
  init(document: DocumentTree, stylesheet: Stylesheet, animations: DocumentAnimations, passes: Int) {
    let changing = animations.smil.indices.filter { Self.changesAttribute(animations.smil[$0]) }
    guard !changing.isEmpty, !animations.keyframes.isEmpty, let root = document.root else { return }
    let schedule = SMILSchedule(animations: animations.smil, until: .infinity, passes: passes)
    var times = Set<Double>()
    var isComplete = schedule.isComplete
    for index in changing {
      for interval in schedule.intervals[index] {
        times.formUnion(Self.times(of: animations.smil[index], in: interval))
      }
    }
    if times.count > Self.maximumTimes {
      isComplete = false
    }
    let sorted = times.sorted().prefix(Self.maximumTimes)
    // The animations that the elements run as the document is loaded start at time zero.
    var running = Self.animations(
      of: ElementCursor(root: root).makeElement(with: stylesheet, languages: document.languages), in: animations
    ).keys
    var attributes = [ElementID: [String: String]]()
    // The times at which the animations that run finish, which an animation that stops running before then doesn't
    // reach.
    var finishes = [CSSAnimationID: Double]()
    for time in sorted {
      let effects = SMILEffect.effects(of: animations.smil, at: time)
      let changed = SMILEffect.attributes(of: effects, in: document)
      guard changed != attributes else { continue }
      attributes = changed
      var animated = animations
      animated.time = time
      animated.smilEffects = effects
      let current = Self.animations(
        of: document.replacingAttributes(changed).root.flatMap {
          ElementCursor(root: $0).makeElement(with: stylesheet, languages: document.languages, animations: animated)
        }, in: animations)
      for (id, finish) in finishes where current[id] == nil {
        end = max(end, min(finish, time))
        finishes[id] = nil
      }
      for (id, (timing, isPaused)) in current where !running.contains(id) {
        starts[id, default: []].append(time)
        if let finish = AnimationPlayback(startTime: time, isPaused: isPaused).timeOfFinish(end: timing.end) {
          finishes[id] = finish
        }
      }
      running = current.keys
    }
    for finish in finishes.values {
      end = max(end, finish)
    }
    if !isComplete {
      end = .infinity
    }
  }

  /// The time that a CSS animation started at, for one that a SMIL animation applies at the time, or `nil` for one
  /// that the elements run as the document is loaded.
  func start(of id: CSSAnimationID, at time: Double) -> Double? {
    starts[id]?.last { $0 <= time }
  }

  /// Whether a SMIL animation changes an attribute of its target that isn't a property, which makes the elements
  /// again, with the rules that match them then.
  private static func changesAttribute(_ animation: SMILAnimation) -> Bool {
    SMILEffect(
      animation: animation, state: SMILState(intervalBegin: 0, iteration: 0, progress: 0, isFrozen: false), order: 0
    ).changesAttribute
  }

  /// The times in an interval of a SMIL animation at which the value that it gives can change: the begin and the end
  /// of the interval, and in each repeat of the simple duration, the times of its values and the times halfway between
  /// them, where the values of a calculation mode that isn't discrete change for attributes that don't interpolate.
  private static func times(of animation: SMILAnimation, in interval: SMILInterval) -> [Double] {
    var times = [interval.begin]
    if interval.playEnd.isFinite {
      times.append(interval.playEnd)
    }
    if interval.end.isFinite {
      times.append(interval.end)
    }
    guard let duration = animation.duration, duration > 0 else { return times }
    let count = max(animation.values.count, 1)
    var fractions = Set(animation.keyTimes ?? [])
    for index in 0...count {
      fractions.insert(Double(index) / Double(count))
      if count > 1 {
        fractions.insert(Double(index) / Double(count - 1))
        fractions.insert((Double(index) + 0.5) / Double(count - 1))
      }
    }
    let keyTimes = (animation.keyTimes ?? []).sorted()
    for (first, second) in zip(keyTimes, keyTimes.dropFirst()) {
      fractions.insert((first + second) / 2)
    }
    var repeatBegin = interval.begin
    while repeatBegin < interval.playEnd, times.count <= maximumTimes {
      for fraction in fractions where (0..<1).contains(fraction) {
        let time = repeatBegin + fraction * duration
        if time < interval.playEnd {
          times.append(time)
        }
      }
      repeatBegin += duration
    }
    return times
  }

  /// The CSS animations that the elements of a tree run, with their timings and whether they're paused.
  private static func animations(
    of root: (any SVGElement)?, in animations: DocumentAnimations
  ) -> [CSSAnimationID: (AnimationTiming, Bool)] {
    var running = [CSSAnimationID: (AnimationTiming, Bool)]()
    for element in root?.elements ?? [] {
      let style = element.style
      for (name, occurrence, index) in style.cssAnimations(keyframes: animations.keyframes) {
        let id = CSSAnimationID(element: element.base.elementID, name: name, occurrence: occurrence)
        running[id] = ElementAnimation.timing(of: style, at: index)
      }
    }
    return running
  }
}
