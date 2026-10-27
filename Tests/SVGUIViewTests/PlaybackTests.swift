import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// A clock that tests advance by hand.
@MainActor
private final class ManualClock: AnimationClock {
  var onFrame: ((Duration) -> Void)?
  var isRunning = false

  /// Shows a frame after the time, if the clock is running.
  func advance(by time: Duration) {
    guard isRunning else { return }
    onFrame?(time)
  }
}

/// Tests that a view plays, pauses and seeks the animations of its document.
@MainActor
@Suite("Playback", .serialized)
struct PlaybackTests {
  /// A document whose square changes from black to lime in one second, and stays lime.
  private static let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <style>@keyframes a { from { fill: rgb(0, 0, 0) } to { fill: rgb(0, 255, 0) } }</style>
      <rect width="20" height="20" fill="red" style="animation: a 1s linear forwards"/>
    </svg>
    """#
  private static let still =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#

  /// How long a test waits for a rendering, which only catches a rendering that never ends.
  private static let patience: Duration = .seconds(60)
  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window, with a clock that the test advances, that has rendered its first image.
  private func makeView(
    _ svg: String = document, animation: SVGUIViewConfiguration.AnimationMode = .play,
    playsWithReduceMotion: Bool = false, isReduceMotionEnabled: Bool = false
  ) async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { isReduceMotionEnabled }
    view.configuration = SVGUIViewConfiguration(
      timeoutDuration: Self.patience, animation: animation, playsWithReduceMotion: playsWithReduceMotion)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    return (view, clock)
  }

  /// The green component of the pixel at the center of what the view shows, in its image or in its layers, or `nil`
  /// if it shows nothing there.
  private func green(in view: SVGUIView) -> UInt8? {
    var components = [UInt8](repeating: 0, count: 4)
    guard
      let context = CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.translateBy(x: -view.bounds.midX, y: -view.bounds.midY)
    view.layer.render(in: context)
    return components[3] == 0 ? nil : components[1]
  }

  /// Waits until the green component at the center of the image that the view shows passes the check.
  private func waitForGreen(
    in view: SVGUIView, sourceLocation: SourceLocation = #_sourceLocation, _ check: (UInt8) -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + Self.patience
    while green(in: view).map(check) != true {
      guard ContinuousClock.now < deadline else {
        Issue.record(
          "The view shows green \(green(in: view).map(String.init) ?? "nil")", sourceLocation: sourceLocation)
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test("the view plays the animations as its clock advances")
  func plays() async throws {
    let (view, clock) = try await makeView()
    #expect(clock.isRunning)
    #expect(green(in: view) == 0)
    clock.advance(by: .milliseconds(250))
    clock.advance(by: .milliseconds(250))
    #expect(view.currentTime == .milliseconds(500))
    try await waitForGreen(in: view) { (127...128).contains($0) }
  }

  @Test("frames that come while a rendering is in progress are skipped to the latest time")
  func skipsFrames() async throws {
    let (view, clock) = try await makeView()
    for _ in 0..<10 {
      clock.advance(by: .milliseconds(100))
    }
    #expect(view.currentTime == .seconds(1))
    try await waitForGreen(in: view) { $0 == 255 }
  }

  @Test("pausing holds the time, and seeking displays a time")
  func pausesAndSeeks() async throws {
    let (view, clock) = try await makeView()
    view.pause()
    #expect(!clock.isRunning)
    clock.advance(by: .milliseconds(500))
    #expect(view.currentTime == .zero)
    view.seek(to: .milliseconds(500))
    #expect(view.currentTime == .milliseconds(500))
    try await waitForGreen(in: view) { (127...128).contains($0) }
    view.seek(to: .seconds(-1))
    #expect(view.currentTime == .zero)
    try await waitForGreen(in: view) { $0 == 0 }
    view.play()
    #expect(clock.isRunning)
  }

  @Test("a paused view starts at time zero, and plays when it's told to")
  func startsPaused() async throws {
    let (view, clock) = try await makeView(animation: .paused)
    #expect(!clock.isRunning)
    view.play()
    #expect(clock.isRunning)
    clock.advance(by: .seconds(2))
    try await waitForGreen(in: view) { $0 == 255 }
  }

  @Test("without animations, the view displays time zero and ignores playback")
  func stillImage() async throws {
    let (view, clock) = try await makeView(animation: .none)
    view.play()
    view.seek(to: .seconds(1))
    #expect(!clock.isRunning)
    #expect(view.currentTime == .zero)
    #expect(green(in: view) == 0)
  }

  @Test("changing the mode to none moves the animations back to time zero")
  func stopsPlaying() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(2))
    try await waitForGreen(in: view) { $0 == 255 }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: Self.patience)
    #expect(!clock.isRunning)
    #expect(view.currentTime == .zero)
    try await waitForGreen(in: view) { $0 == 0 }
  }

  @Test("the clock doesn't run for a document without animations")
  func documentWithoutAnimations() async throws {
    let (view, clock) = try await makeView(Self.still)
    #expect(!clock.isRunning)
    view.data = Data(Self.document.utf8)
    #expect(clock.isRunning)
  }

  @Test("new data moves the animations back to time zero")
  func newData() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(2))
    view.data = Data(Self.document.replacingOccurrences(of: "1s", with: "2s").utf8)
    #expect(view.currentTime == .zero)
    try await waitForGreen(in: view) { $0 == 0 }
  }

  @Test("the animations don't advance while the view can't be seen")
  func stopsWhileHidden() async throws {
    let (view, clock) = try await makeView()
    view.isHidden = true
    #expect(!clock.isRunning)
    view.isHidden = false
    #expect(clock.isRunning)
    view.removeFromSuperview()
    #expect(!clock.isRunning)
    window.addSubview(view)
    #expect(clock.isRunning)
    view.frame.size = .zero
    view.layoutIfNeeded()
    #expect(!clock.isRunning)
  }

  @Test("the animations don't advance while the app is in the background")
  func stopsInBackground() async throws {
    let (_, clock) = try await makeView()
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    #expect(!clock.isRunning)
    NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    #expect(clock.isRunning)
  }

  @Test("Reduce Motion holds the animations at time zero, unless the configuration plays them anyway")
  func reduceMotion() async throws {
    let (view, clock) = try await makeView(isReduceMotionEnabled: true)
    #expect(!clock.isRunning)
    view.seek(to: .milliseconds(500))
    #expect(green(in: view) == 0)
    // The view follows the setting when it changes.
    view.isReduceMotionEnabled = { false }
    #expect(clock.isRunning)
    try await waitForGreen(in: view) { (127...128).contains($0) }

    let (_, anywayClock) = try await makeView(playsWithReduceMotion: true, isReduceMotionEnabled: true)
    #expect(anywayClock.isRunning)
  }

  @Test("the clock stops after the frame that passes the end of the animations, and runs again before it")
  func stopsAtEnd() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .milliseconds(500))
    #expect(clock.isRunning)
    clock.advance(by: .milliseconds(600))
    #expect(!clock.isRunning)
    #expect(view.currentTime == .milliseconds(1100))
    try await waitForGreen(in: view) { $0 == 255 }
    view.seek(to: .milliseconds(500))
    #expect(clock.isRunning)
    try await waitForGreen(in: view) { (127...128).contains($0) }
  }

  @Test("the clock keeps running for animations that don't end")
  func infiniteAnimation() async throws {
    let (_, clock) = try await makeView(Self.document.replacingOccurrences(of: "forwards", with: "infinite"))
    clock.advance(by: .seconds(100))
    #expect(clock.isRunning)
  }

  @Test("the clock doesn't run for animations that don't change the document")
  func pausedAnimation() async throws {
    let (_, clock) = try await makeView(Self.document.replacingOccurrences(of: "forwards", with: "paused"))
    #expect(!clock.isRunning)
  }

  @Test("a view that can play animations shows its document in layers, and one that can't in an image")
  func showsLayers() async throws {
    let (view, _) = try await makeView()
    #expect(view.layer.contents == nil)
    #expect(view.layer.sublayers?.isEmpty == false)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: Self.patience)
    let deadline = ContinuousClock.now + Self.patience
    while view.layer.contents == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(view.layer.contents != nil)
    #expect(view.layer.sublayers?.isEmpty ?? true)
    #expect(green(in: view) == 0)
  }

  @Test("a rendering into layers that fails keeps what the view shows, unless there's nothing to show")
  func failedLayers() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(2))
    try await waitForGreen(in: view) { $0 == 255 }
    view.showLayers(.failure(.timedOut))
    view.showLayers(.failure(.allocationFailed))
    #expect(green(in: view) == 255)
    view.showLayers(.failure(.missingRootElement))
    #expect(green(in: view) == nil)
  }
}
