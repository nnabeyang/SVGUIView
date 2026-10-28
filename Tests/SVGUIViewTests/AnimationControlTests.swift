import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app controls the CSS animations of a view's document, and that the animations that a change starts
/// start at the time of the change.
@MainActor
@Suite("Controlling animations", .serialized, .timeLimit(.minutes(2)))
struct AnimationControlTests {
  /// A document whose square turns from black to lime in one second when it runs `a`, and whose circle, outside the
  /// center, runs `a` for two seconds as the document is loaded.
  private static let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <style>
        @keyframes a { from { fill: rgb(0, 0, 0) } to { fill: rgb(0, 255, 0) } }
        .run { animation: a 1s linear forwards }
      </style>
      <rect id="square" width="20" height="20" fill="red"/>
      <circle id="circle" r="1" style="animation: a 2s linear forwards"/>
    </svg>
    """#

  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window, with a clock that the test advances, that has rendered its first image.
  private func makeView(
    animation: SVGUIViewConfiguration.AnimationMode = .play
  ) async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(Self.document.utf8))
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: animation)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    return (view, clock)
  }

  /// The animation of the square, which starts it.
  private func startSquare(in view: SVGUIView) throws -> SVGDocument.Animation {
    let square = try #require(view.document.element(id: "square"))
    square.classList.add("run")
    return try #require(square.animations.first)
  }

  /// Lets the run loop display the layer of the view.
  private func display() async throws {
    try await Task.sleep(for: .milliseconds(50))
  }

  @Test("the document lists the CSS animations that its elements run, with the changes made so far")
  func listsAnimations() async throws {
    let (view, _) = try await makeView()
    #expect(view.document.animations.map { $0.element.attribute("id") } == ["circle"])
    let animation = try startSquare(in: view)
    #expect(animation.animationName == "a")
    #expect(view.document.animations.map { $0.element.attribute("id") } == ["square", "circle"])
    #expect(try #require(view.document.element(id: "circle")).animations.count == 1)
  }

  @Test("an animation that a change starts starts at the time of the change")
  func startsAtChange() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(5))
    let animation = try startSquare(in: view)
    #expect(animation.currentTime == .zero)
    try await waitForGreen(in: view) { $0 == 0 }
    clock.advance(by: .milliseconds(500))
    try await waitForGreen(in: view) { (126...129).contains($0) }
  }

  @Test("pausing holds an animation, playing plays it on, and setting its time moves it")
  func pausesPlaysAndSeeks() async throws {
    let (view, clock) = try await makeView()
    let animation = try startSquare(in: view)
    clock.advance(by: .milliseconds(250))
    animation.pause()
    #expect(animation.isPaused)
    clock.advance(by: .milliseconds(500))
    #expect(animation.currentTime == .milliseconds(250))
    try await waitForGreen(in: view) { (62...65).contains($0) }
    animation.currentTime = .milliseconds(500)
    try await waitForGreen(in: view) { (126...129).contains($0) }
    animation.play()
    #expect(!animation.isPaused)
    clock.advance(by: .milliseconds(250))
    #expect(animation.currentTime == .milliseconds(750))
    try await waitForGreen(in: view) { (189...192).contains($0) }
  }

  @Test("an animation plays at its playback rate")
  func playbackRate() async throws {
    let (view, clock) = try await makeView()
    let animation = try startSquare(in: view)
    #expect(animation.playbackRate == 1)
    animation.playbackRate = 2
    clock.advance(by: .milliseconds(250))
    #expect(animation.currentTime == .milliseconds(500))
    try await waitForGreen(in: view) { (126...129).contains($0) }
  }

  @Test("waiting for an animation to finish returns after it reaches its end")
  func finished() async throws {
    let (view, clock) = try await makeView()
    let animation = try startSquare(in: view)
    var hasFinished = false
    let waiter = Task {
      await animation.finished()
      hasFinished = true
    }
    try await display()
    clock.advance(by: .milliseconds(900))
    try await display()
    #expect(!hasFinished)
    clock.advance(by: .milliseconds(200))
    await waiter.value
    #expect(hasFinished)
    // An animation that has finished doesn't wait.
    await animation.finished()
  }

  @Test("waiting for an animation returns when the element no longer runs it, or the view replaces the document")
  func finishedWithoutAnimation() async throws {
    let (view, _) = try await makeView()
    let animation = try startSquare(in: view)
    let removed = Task { await animation.finished() }
    try await display()
    try #require(view.document.element(id: "square")).classList.remove("run")
    try await display()
    await removed.value
    #expect(animation.currentTime == nil)
    let circle = try #require(view.document.animations.first)
    let replaced = Task { await circle.finished() }
    try await display()
    view.data = Data((Self.document + "<!-- new -->").utf8)
    await replaced.value
    // The document that the view no longer shows has no animations.
    #expect(circle.element.document.animations.isEmpty)
    #expect(circle.currentTime == nil)
  }

  @Test("moving an animation back runs the clock that stopped at the end of the animations")
  func runsClockAgain() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(3))
    #expect(!clock.isRunning)
    let circle = try #require(view.document.animations.first)
    circle.currentTime = .seconds(1)
    #expect(clock.isRunning)
  }

  @Test("a view that doesn't play shows an animation at the time that it's moved to")
  func stillImage() async throws {
    let (view, _) = try await makeView(animation: .none)
    let animation = try startSquare(in: view)
    try await waitForGreen(in: view) { $0 == 0 }
    animation.currentTime = .milliseconds(500)
    try await waitForGreen(in: view) { (126...129).contains($0) }
  }
}
