import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a change of a view's document starts CSS transitions, which the view plays.
@MainActor
@Suite("Playing transitions", .serialized, .timeLimit(.minutes(2)))
struct TransitionTests {
  /// A document whose square turns from black to lime in one second when it gets `on`.
  private static let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <style>
        rect { fill: rgb(0, 0, 0); transition: fill 1s linear }
        .on { fill: rgb(0, 255, 0) }
      </style>
      <rect id="square" width="20" height="20"/>
    </svg>
    """#

  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window, with a clock that the test advances, that has rendered its first image.
  private func makeView(
    animation: SVGUIViewConfiguration.AnimationMode = .play, reduceMotion: Bool = false
  ) async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(Self.document.utf8))
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { reduceMotion }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: animation)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { $0 == 0 }
    return (view, clock)
  }

  @Test("a change starts a transition at the time that the view displays, which runs the clock until it ends")
  func playsTransition() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(5))
    #expect(!clock.isRunning)
    try #require(view.document.element(id: "square")).classList.add("on")
    // The run loop displays the layer of the view, which applies the change.
    try await Task.sleep(for: .milliseconds(50))
    try await waitForGreen(in: view) { $0 == 0 }
    #expect(clock.isRunning)
    clock.advance(by: .milliseconds(500))
    try await waitForGreen(in: view) { (126...129).contains($0) }
    clock.advance(by: .milliseconds(600))
    try await waitForGreen(in: view) { $0 == 255 }
    #expect(!clock.isRunning)
  }

  @Test(
    "a view that doesn't play animations, or that Reduce Motion holds, shows the new value at once",
    arguments: [(SVGUIViewConfiguration.AnimationMode.none, false), (.play, true)])
  func withoutMotion(animation: SVGUIViewConfiguration.AnimationMode, reduceMotion: Bool) async throws {
    let (view, clock) = try await makeView(animation: animation, reduceMotion: reduceMotion)
    try #require(view.document.element(id: "square")).classList.add("on")
    try await waitForGreen(in: view) { $0 == 255 }
    #expect(!clock.isRunning)
  }
}
