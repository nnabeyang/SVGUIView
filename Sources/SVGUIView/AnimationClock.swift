import QuartzCore

/// A clock that tells a view when to show the next frame of its animations, and how much time passed since the
/// frame before.
///
/// Tests replace the display link with a clock that they advance by hand.
@MainActor
protocol AnimationClock: AnyObject {
  /// Called for each frame with the time since the previous frame, which is zero for the first frame after the
  /// clock starts, so that the time doesn't advance while the clock is stopped.
  var onFrame: ((Duration) -> Void)? { get set }
  /// Whether the clock calls ``onFrame`` for frames.
  var isRunning: Bool { get set }
}

/// A clock that advances with the frames of the display.
@MainActor
final class DisplayLinkClock: AnimationClock {
  var onFrame: ((Duration) -> Void)?
  var isRunning = false {
    didSet {
      guard isRunning != oldValue else { return }
      if isRunning {
        // The display link retains its target, so it retains a proxy that holds the clock weakly.
        let link = CADisplayLink(target: Target(clock: self), selector: #selector(Target.frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
      } else {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
      }
    }
  }
  private var displayLink: CADisplayLink?
  /// The time that the previous frame was shown at.
  private var previousTimestamp: CFTimeInterval?

  private func frame(_ link: CADisplayLink) {
    // The target timestamp is when the frame will be shown, which the animations are sampled at.
    let timestamp = link.targetTimestamp
    let elapsed = previousTimestamp.map { max(timestamp - $0, 0) } ?? 0
    previousTimestamp = timestamp
    onFrame?(.seconds(elapsed))
  }

  private final class Target: NSObject {
    weak var clock: DisplayLinkClock?

    init(clock: DisplayLinkClock) {
      self.clock = clock
    }

    @MainActor @objc func frame(_ link: CADisplayLink) {
      // A released clock can't invalidate its display link, so the link stops at its next frame.
      guard let clock else {
        link.invalidate()
        return
      }
      clock.frame(link)
    }
  }
}
