import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app begins and ends the SMIL animations of a view's document from their elements.
@MainActor
@Suite("Beginning and ending SMIL animations", .serialized, .timeLimit(.minutes(2)))
struct SMILControlTests {
  /// A document whose square turns from black to lime in one second when the app begins its animation, and whose
  /// circle, outside the center, moves for two seconds as the document is loaded.
  private static let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <rect width="20" height="20" fill="red">
        <animate id="a" attributeName="fill" from="rgb(0, 0, 0)" to="rgb(0, 255, 0)" begin="indefinite" dur="1s"/>
      </rect>
      <circle id="c" r="1"><animate attributeName="cx" to="2" dur="2s"/></circle>
    </svg>
    """#

  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window, with a clock that the test advances, that has rendered its first image.
  private func makeView() async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(Self.document.utf8))
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .play)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    return (view, clock)
  }

  @Test("an app begins an animation at the time that the view displays, and ends it")
  func beginsAndEnds() async throws {
    let (view, clock) = try await makeView()
    let animation = try #require(view.document.element(id: "a"))
    // The square is red, which has no green, until the animation begins.
    clock.advance(by: .seconds(5))
    try await waitForGreen(in: view) { $0 == 0 }
    animation.beginElement()
    clock.advance(by: .milliseconds(500))
    try await waitForGreen(in: view) { (126...129).contains($0) }
    // The animation doesn't freeze, so the square is red again after it ends.
    animation.endElement()
    try await waitForGreen(in: view) { $0 == 0 }
  }

  @Test("beginning an animation runs the clock that stopped at the end of the animations")
  func runsClock() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(3))
    #expect(!clock.isRunning)
    try #require(view.document.element(id: "a")).beginElement()
    #expect(clock.isRunning)
    clock.advance(by: .seconds(2))
    #expect(!clock.isRunning)
  }

  @Test("elements that aren't animations, and the elements of a document that a view no longer shows, do nothing")
  func otherElements() async throws {
    let (view, clock) = try await makeView()
    clock.advance(by: .seconds(3))
    try #require(view.document.element(id: "c")).beginElement()
    #expect(!clock.isRunning)
    let animation = try #require(view.document.element(id: "a"))
    view.data = Data((Self.document + "<!-- new -->").utf8)
    // The animations of the new document end, and the element of the old one doesn't begin them again.
    clock.advance(by: .seconds(3))
    #expect(!clock.isRunning)
    animation.beginElement()
    #expect(!clock.isRunning)
  }
}
