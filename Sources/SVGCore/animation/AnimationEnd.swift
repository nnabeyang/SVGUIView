import Foundation

extension SVGBaseContext {
  /// The most passes of the schedule that finds the end of the SMIL animations, which is how many animations a
  /// chain of syncbase values can have.
  private static let endPasses = 100

  /// The time in seconds after which the computed values of the document don't change, which is 0 for a document
  /// without animations and infinite for animations that don't end.
  ///
  /// After an animation or a transition ends, it keeps its last value or has no effect, so the document looks the
  /// same at any later time. The CSS animations are the ones that the elements run as the document is loaded: one that a SMIL
  /// animation starts by changing `class` or `style` isn't counted.
  ///
  /// This finds the intervals of every SMIL animation, so a renderer calls it once for a document, not for the
  /// documents at each time.
  package func animationEnd() -> Double {
    guard isAnimated, let root else { return 0 }
    var end = 0.0
    for element in root.elements {
      let style = element.style
      for (name, occurrence, index) in style.cssAnimations(keyframes: animations.keyframes) {
        let id = CSSAnimationID(element: element.base.elementID, name: name, occurrence: occurrence)
        let (timing, isPaused) = ElementAnimation.timing(of: style, at: index)
        // A paused animation stays where it is.
        guard let finish = animations.playback(of: id, isPaused: isPaused).timeOfFinish(end: timing.end) else {
          continue
        }
        end = max(end, finish)
      }
    }
    for transitions in animations.transitions.values {
      for transition in transitions.values {
        end = max(end, transition.endTime)
      }
    }
    // Animations that keep beginning again, such as ones that begin when the other ends, add intervals in every
    // pass, so they don't end. So does a longer chain of syncbase values than the passes, which only keeps the
    // clock running.
    let schedule = SMILSchedule(animations: animations.smil, until: .infinity, passes: Self.endPasses)
    guard schedule.isComplete else { return .infinity }
    for interval in schedule.intervals.joined() {
      end = max(end, interval.end)
    }
    return end
  }
}
