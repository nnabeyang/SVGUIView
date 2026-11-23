import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the SMIL and CSS animations of SVG images run on the timeline of the document that shows them, as the
/// secure animated mode of SVG Integration has them.
@MainActor
@Suite("Animated SVG images", .serialized, .timeLimit(.minutes(2)))
struct AnimatedImageTests {
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A data URL of an SVG image.
  private static func url(_ svg: String) -> String {
    "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
  }

  /// An image whose left half is red and right half green, whose view box shows only the right half from 0.2 s, as
  /// the WPT test `image-preserveaspectratio-none-animated-viewbox` has it.
  private static let viewBoxImage = url(
    #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
    <rect width="50" height="100" fill="red"/><rect x="50" width="50" height="100" fill="rgb(0, 255, 0)"/>
    <set attributeName="viewBox" to="50 0 50 100" begin="0.2s" fill="freeze"/>
    </svg>
    """#)

  /// An image whose square changes from black to lime in one second, and stays lime.
  private static let colorImage = url(
    #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
    <style>@keyframes a { from { fill: rgb(0, 0, 0) } to { fill: rgb(0, 255, 0) } }</style>
    <rect width="20" height="20" fill="red" style="animation: a 1s linear forwards"/>
    </svg>
    """#)

  private func view(_ content: String) -> SVGUIView {
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 20, height: 20),
      data: Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">\#(content)</svg>"#.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    return view
  }

  /// The red, green, blue and alpha components of a pixel of a snapshot of the view at a time.
  private func pixel(of view: SVGUIView, at time: Duration, x: Int = 10, y: Int = 10) async throws -> [UInt8] {
    let image = try #require(try await view.takeSnapshot(at: time, scale: 1).cgImage)
    return Rendering(components: try pixels(of: image), width: image.width, scale: 1).pixel(x: x, y: y)
  }

  /// A view in the window that plays its animations on a clock that the test advances, once it shows the document.
  private func playingView(_ content: String) async throws -> (SVGUIView, ManualClock) {
    let view = view(content)
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .play)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    try await waitForRendering(of: view)
    return (view, clock)
  }

  @Test("an animation of the view box of the root of an SVG image changes the image at its time")
  func viewBox() async throws {
    let view = view(
      #"<image href="\#(Self.viewBoxImage)" width="20" height="20" preserveAspectRatio="none"/>"#)
    #expect(try await pixel(of: view, at: .zero, x: 2) == [255, 0, 0, 255])
    #expect(try await pixel(of: view, at: .milliseconds(100), x: 2) == [255, 0, 0, 255])
    #expect(try await pixel(of: view, at: .milliseconds(300), x: 2) == [0, 255, 0, 255])
    #expect(try await pixel(of: view, at: .milliseconds(300), x: 17) == [0, 255, 0, 255])
  }

  @Test("a CSS animation of an SVG image, an SVG image in it, and one that a feImage draws, are at the time")
  func cssAnimation() async throws {
    let nested = Self.url(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><image href="\#(Self.colorImage)" width="20" height="20"/></svg>"#
    )
    for content in [
      #"<image href="\#(Self.colorImage)" width="20" height="20"/>"#,
      #"<image href="\#(nested)" width="20" height="20"/>"#,
      #"<filter id="f" x="0" y="0" width="1" height="1"><feImage href="\#(Self.colorImage)"/></filter><rect width="20" height="20" filter="url(#f)"/>"#,
    ] {
      let view = view(content)
      #expect(try await pixel(of: view, at: .zero) == [0, 0, 0, 255], "\(content)")
      let halfway = try await pixel(of: view, at: .milliseconds(500))
      #expect((127...128).contains(halfway[1]) && halfway[0] == 0, "\(content) \(halfway)")
      #expect(try await pixel(of: view, at: .seconds(2)) == [0, 255, 0, 255], "\(content)")
    }
  }

  @Test("the animations of an SVG image play in a view, and end where the animations of the image end")
  func playing() async throws {
    let (view, clock) = try await playingView(#"<image href="\#(Self.colorImage)" width="20" height="20"/>"#)
    #expect(green(in: view) == 0)
    // The first rendering finds the animations of the image, which make the clock run.
    #expect(view.document.animationEnd == .seconds(1))
    try await waitUntil("The clock doesn't run") { clock.isRunning }
    clock.advance(by: .milliseconds(500))
    try await waitForGreen(in: view) { (127...128).contains($0) }
    clock.advance(by: .milliseconds(600))
    try await waitForGreen(in: view) { $0 == 255 }
    try await waitUntil("The clock still runs after the animations of the image end") { !clock.isRunning }
  }

  @Test("a paused view that shows still frames in layers shows an SVG image at the time that it seeks to")
  func seekInLayers() async throws {
    let view = view(#"<image href="\#(Self.colorImage)" width="20" height="20"/>"#)
    view.clock = ManualClock()
    view.isReduceMotionEnabled = { false }
    view.showsStillFramesInLayers = true
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .paused)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    try await waitForRendering(of: view)
    #expect(green(in: view) == 0)
    view.seek(to: .milliseconds(500))
    try await waitForGreen(in: view) { (127...128).contains($0) }
    view.seek(to: .seconds(2))
    try await waitForGreen(in: view) { $0 == 255 }
  }

  @Test("an SVG image in a pattern animates, as every layer is painted again")
  func pattern() async throws {
    let (view, clock) = try await playingView(
      #"<pattern id="p" width="1" height="1"><image href="\#(Self.colorImage)" width="20" height="20"/></pattern>"#
        + #"<rect width="20" height="20" fill="url(#p)"/>"#)
    #expect(green(in: view) == 0)
    try await waitUntil("The clock doesn't run") { clock.isRunning }
    clock.advance(by: .seconds(2))
    try await waitForGreen(in: view) { $0 == 255 }
  }

  @Test("Reduce Motion and a view that doesn't play its animations show an SVG image at time zero")
  func heldAnimations() async throws {
    let view = view(#"<image href="\#(Self.colorImage)" width="20" height="20"/>"#)
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { true }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .play)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    try await waitForRendering(of: view)
    #expect(!clock.isRunning)
    #expect(green(in: view) == 0)
  }

  @Test("a document without animated images doesn't run its clock")
  func stillImage() async throws {
    let still = Self.url(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20" fill="rgb(0, 255, 0)"/></svg>"#
    )
    let (view, clock) = try await playingView(#"<image href="\#(still)" width="20" height="20"/>"#)
    #expect(green(in: view) == 255)
    #expect(!clock.isRunning)
    #expect(view.document.animationEnd == .zero)
  }
}
