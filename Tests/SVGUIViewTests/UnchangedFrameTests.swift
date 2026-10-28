import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a playing view doesn't render the frames whose animated values are the same as those of the frame that
/// it shows.
@MainActor
@Suite("Skipping unchanged frames", .serialized, .timeLimit(.minutes(2)))
struct UnchangedFrameTests {
  /// A document whose square turns from black to green in steps, or continuously.
  private static func document(easing: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <style>
        @keyframes k { from { fill: rgb(0, 0, 0) } to { fill: rgb(0, 255, 0) } }
        rect { animation: k 1s \(easing) }
      </style>
      <rect width="20" height="20"/>
    </svg>
    """
  }

  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window, with a clock that the test advances, that has rendered its first image.
  private func makeView(easing: String) async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(Self.document(easing: easing).utf8))
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .play)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await settle(view)
    return (view, clock)
  }

  /// Waits until the view has finished rendering.
  private func settle(_ view: SVGUIView) async throws {
    let deadline = ContinuousClock.now + patience
    repeat {
      try await Task.sleep(for: .milliseconds(20))
    } while view.isRendering && ContinuousClock.now < deadline
  }

  /// Advances the clock by a frame, and waits until the view has rendered it.
  private func advance(_ clock: ManualClock, by time: Duration, in view: SVGUIView) async throws {
    clock.advance(by: time)
    try await settle(view)
  }

  @Test("the frames within a step of an animation aren't rendered, and the frame of the next step is")
  func steps() async throws {
    let (view, clock) = try await makeView(easing: "steps(2, end)")
    for _ in 0..<4 {
      try await advance(clock, by: .milliseconds(100), in: view)
    }
    #expect(view.unchangedFrameCount == 4)
    #expect(green(in: view) == 0)
    try await advance(clock, by: .milliseconds(200), in: view)
    #expect(view.unchangedFrameCount == 4)
    try await waitForGreen(in: view) { (126...129).contains($0) }
  }

  @Test("every frame of a continuous animation is rendered")
  func continuous() async throws {
    let (view, clock) = try await makeView(easing: "linear")
    for _ in 0..<4 {
      try await advance(clock, by: .milliseconds(100), in: view)
    }
    #expect(view.unchangedFrameCount == 0)
  }

  @Test("the frame after a change of how an animation plays is rendered, even if its values are the same")
  func changedPlayback() async throws {
    let (view, clock) = try await makeView(easing: "steps(2, end)")
    try await advance(clock, by: .milliseconds(100), in: view)
    #expect(view.unchangedFrameCount == 1)
    let animation = try #require(view.document.animations.first)
    animation.currentTime = .milliseconds(200)
    try await settle(view)
    #expect(view.unchangedFrameCount == 1)
    try await advance(clock, by: .milliseconds(100), in: view)
    #expect(view.unchangedFrameCount == 2)
  }
}
