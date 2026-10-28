import Foundation

/// A transition of a property of an element, which a change of the document starts, in the terms of CSS Transitions.
struct CSSTransition: Sendable {
  /// The computed values of the property that the transition starts from and ends at.
  let startValue: any Sendable
  let endValue: any Sendable
  /// The time of the timeline at which the change that started the transition was made, in seconds. Before it, as
  /// when the document is moved back to an earlier time, the transition has no effect.
  let changeTime: Double
  /// The time at which the value starts changing, after the delay.
  let startTime: Double
  let duration: Double
  let easing: EasingFunction
  /// The value that changing the property back to reverses the transition, which is the start value of the
  /// transition that this one reverses, if any.
  let reversingAdjustedStartValue: any Sendable
  /// How much shorter the transition is than its duration and delay give, because it reverses another one.
  let reversingShorteningFactor: Double

  /// The time at which the transition ends, after which it has no effect.
  var endTime: Double {
    startTime + duration
  }

  /// Whether the transition has an effect at the time or later.
  func isRunning(at time: Double) -> Bool {
    changeTime <= time && time < endTime
  }

  /// The progress of the transition at a time after its easing function, which is the start value's during the
  /// delay and the end value's after the end.
  func easedProgress(at time: Double) -> Double {
    let progress = duration > 0 ? min(max((time - startTime) / duration, 0), 1) : time < startTime ? 0 : 1
    return easing(progress, before: time < startTime)
  }

  /// The value of the property at a time, which is the start value during the delay, or `nil` when the transition
  /// has no effect.
  func value<P: StyleProperty>(of _: P.Type, at time: Double, in resolver: StyleResolver) -> P.Computed? {
    guard isRunning(at: time), let start = startValue as? P.Computed, let end = endValue as? P.Computed else {
      return nil
    }
    return P.interpolated(start, end, progress: easedProgress(at: time), in: resolver)
  }
}

extension SVGBaseContext {
  /// The transitions of the elements of a changed context, which the change starts, reverses or cancels, as CSS
  /// Transitions specifies for a style change event.
  ///
  /// Each property whose computed value the change changes starts a transition, when `transition-property` names it
  /// and its duration and delay add up to more than zero, and the two values interpolate or `transition-behavior`
  /// is `allow-discrete`. The values that are compared are the ones at the time, with the animations: the value
  /// before the change has the running transitions too, and the value after it doesn't. So a change of a value that
  /// an animation changes starts no transition.
  ///
  /// - Parameters:
  ///   - changed: The context after the change, without transitions.
  ///   - elements: The elements whose computed values the change can change.
  ///   - time: The time of the timeline at which the change is made, in seconds.
  func transitions(changingTo changed: SVGBaseContext, of elements: Set<ElementID>, at time: Double)
    -> [ElementID: [PropertyID: CSSTransition]]
  {
    var transitions = runningTransitions(at: time)
    // The elements that the change can start transitions of, with the `transition-*` values after the change, and
    // the ones whose running transitions it can change.
    let updated = Set(
      (changed.root?.elements ?? []).lazy.filter { element in
        let id = element.base.elementID
        return elements.contains(id) && (transitions[id] != nil || element.style.startsTransitions)
      }.map(\.base.elementID))
    guard !updated.isEmpty else { return transitions }
    let before = Dictionary(
      (at(time: time).root?.elements ?? []).lazy.filter { updated.contains($0.base.elementID) }.map {
        ($0.base.elementID, $0.style)
      }, uniquingKeysWith: { first, _ in first })
    for element in changed.at(time: time).root?.elements ?? [] where updated.contains(element.base.elementID) {
      let id = element.base.elementID
      guard let style = before[id] else { continue }
      var update = TransitionUpdate(
        before: style, after: element.style, time: time, transitions: transitions[id] ?? [:])
      for property in element.style.transitionedProperties(running: update.transitions.keys) {
        property.visit(&update)
      }
      transitions[id] = update.transitions.isEmpty ? nil : update.transitions
    }
    return transitions
  }

  /// The transitions that have an effect at the time or later.
  func runningTransitions(at time: Double) -> [ElementID: [PropertyID: CSSTransition]] {
    animations.transitions.compactMapValues { transitions in
      let running = transitions.filter { $0.value.isRunning(at: time) }
      return running.isEmpty ? nil : running
    }
  }
}

extension ComputedStyle {
  /// Whether a change of a property can start a transition: `transition-property` names a property for which the
  /// duration and the delay add up to more than zero.
  fileprivate var startsTransitions: Bool {
    transitionProperty.indices.contains { index in
      transitionProperty[index] != .none && transitionTiming(at: index).combinedDuration > 0
    }
  }

  /// The properties whose transitions a change can start, reverse or cancel: the ones that `transition-property`
  /// names, or every property that animations change for `all`, and the ones with running transitions.
  fileprivate func transitionedProperties(running: some Collection<PropertyID>) -> [PropertyID] {
    if transitionProperty.contains(.all) { return animatableProperties }
    var properties = Set(running)
    for case .property(let id) in transitionProperty where id.isAnimatable {
      properties.insert(id)
    }
    return Array(properties)
  }

  /// The timing of the transition at an index of `transition-property`. The other lists repeat to its length.
  fileprivate func transitionTiming(at index: Int) -> TransitionTiming {
    func value<T>(_ list: [T], _ initial: T) -> T {
      list.isEmpty ? initial : list[index % list.count]
    }
    return TransitionTiming(
      duration: max(value(transitionDuration, 0), 0), delay: value(transitionDelay, 0),
      easing: value(transitionTimingFunction, .ease), behavior: value(transitionBehavior, .normal))
  }
}

/// The properties that animations change, in the order of ``PropertyID``.
private let animatableProperties = PropertyID.allCases.filter(\.isAnimatable)

/// The values of the `transition-*` properties for a property.
private struct TransitionTiming {
  let duration: Double
  let delay: Double
  let easing: EasingFunction
  let behavior: TransitionBehavior

  var combinedDuration: Double {
    duration + delay
  }
}

/// Updates the transitions of an element for a change, one property at a time.
private struct TransitionUpdate: StylePropertyVisitor {
  /// The computed values before the change, with the running transitions.
  let before: ComputedStyle
  /// The computed values after the change, without transitions.
  let after: ComputedStyle
  let time: Double
  /// The running transitions of the element, which the change updates.
  var transitions: [PropertyID: CSSTransition]

  mutating func visit<P: StyleProperty>(_: P.Type) {
    let current = before[keyPath: P.computed]
    let value = after[keyPath: P.computed]
    let running = transitions[P.id]
    // The last value of `transition-property` that names the property applies.
    guard
      let index = after.transitionProperty.lastIndex(where: { $0 == .all || $0 == .property(P.id) })
    else {
      transitions[P.id] = nil
      return
    }
    // A running transition to the same value goes on.
    if let running, let end = running.endValue as? P.Computed, end == value { return }
    transitions[P.id] = nil
    let timing = after.transitionTiming(at: index)
    guard current != value, timing.combinedDuration > 0 else { return }
    // Whether the values interpolate is asked only for a value that changes, since the resolver copies the values.
    guard
      timing.behavior == .allowDiscrete
        || P.interpolates(current, value, in: StyleResolver(style: after, parent: .initial, root: .initial))
    else { return }
    // A change back to the value that a running transition started from reverses it from where it is, in the part
    // of the time that it has taken so far.
    if let running, let start = running.reversingAdjustedStartValue as? P.Computed, start == value {
      let factor = min(
        max(
          abs(
            running.easedProgress(at: time) * running.reversingShorteningFactor + 1
              - running.reversingShorteningFactor), 0), 1)
      transitions[P.id] = CSSTransition(
        startValue: current, endValue: value, changeTime: time,
        startTime: time + (timing.delay < 0 ? timing.delay * factor : timing.delay),
        duration: timing.duration * factor, easing: timing.easing, reversingAdjustedStartValue: running.endValue,
        reversingShorteningFactor: factor)
      return
    }
    transitions[P.id] = CSSTransition(
      startValue: current, endValue: value, changeTime: time, startTime: time + timing.delay,
      duration: timing.duration, easing: timing.easing, reversingAdjustedStartValue: current,
      reversingShorteningFactor: 1)
  }
}
