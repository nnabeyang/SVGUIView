import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("SVGUIView")
struct SVGUIViewTests {
  private func makeView(_ svg: String, timeoutDuration: Duration = .seconds(10)) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: timeoutDuration)
    return view
  }

  private func makeImage() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return try #require(context.makeImage())
  }

  private static let square =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#

  /// The width in pixels of the image that the view shows.
  private func shownWidth(_ view: SVGUIView) -> Int? {
    guard let contents = view.layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return nil }
    return (contents as! CGImage).width
  }

  /// Waits until the view shows an image of the given width in points, which a rendering in the background
  /// shows when it finishes.
  private func waitForImage(
    in view: SVGUIView, width: CGFloat, sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let pixels = Int((width * UIScreen.main.scale).rounded(.up))
    let deadline = ContinuousClock.now + .seconds(10)
    while shownWidth(view) != pixels {
      guard ContinuousClock.now < deadline else {
        Issue.record(
          "The view shows an image \(shownWidth(view).map(String.init) ?? "nil") pixels wide, not \(pixels)",
          sourceLocation: sourceLocation)
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  /// Renders the view as UIKit does when it displays the view.
  private func render(_ view: SVGUIView) {
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
  }

  @Test("a snapshot is the rendered document")
  func takeSnapshot() async throws {
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#)
    let image = try await view.takeSnapshot()
    // The image is rendered at the screen's scale.
    let pixels = Int(20 * UIScreen.main.scale)
    #expect(image.cgImage?.width == pixels)
    #expect(image.cgImage?.height == pixels)
  }

  @Test("a snapshot of a document without a root svg element throws missingRootElement")
  func takeSnapshotWithoutRootElement() async {
    let view = makeView(#"<svg xmlns="http://www.example.org/notsvg"><rect width="20" height="20"/></svg>"#)
    await #expect(throws: SVGRenderingError.missingRootElement) {
      try await view.takeSnapshot()
    }
  }

  @Test(
    "a snapshot of a rectangle without a width or a height throws zeroSizedRect",
    arguments: [
      CGRect(x: 0, y: 0, width: 0, height: 20),
      CGRect(x: 0, y: 0, width: 20, height: 0),
    ])
  func takeSnapshotOfZeroSizedRect(rect: CGRect) async {
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#)
    await #expect(throws: SVGRenderingError.zeroSizedRect) {
      try await view.takeSnapshot(rect: rect)
    }
  }

  @Test("a snapshot of a view without a size throws zeroSizedRect")
  func takeSnapshotOfZeroSizedView() async {
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#)
    view.frame = .zero
    await #expect(throws: SVGRenderingError.zeroSizedRect) {
      try await view.takeSnapshot()
    }
  }

  @Test("a snapshot that takes longer than the timeout throws timedOut")
  func takeSnapshotTimesOut() async {
    // Rendering checks for cancellation between elements, so many groups make it stop soon after the timeout.
    let groups = String(repeating: #"<g><rect width="20" height="20"/></g>"#, count: 10_000)
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">\#(groups)</svg>"#, timeoutDuration: .zero)
    await #expect(throws: SVGRenderingError.timedOut) {
      try await view.takeSnapshot()
    }
  }

  @Test("a rendering that times out stops in the middle of a filter")
  func timeoutStopsFilter() async throws {
    // A long chain of blurs is the slowest part of the rendering, and it is a single element.
    let blurs = String(repeating: #"<feGaussianBlur stdDeviation="10"/>"#, count: 10_000)
    let view = makeView(
      #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <filter id="blur">\#(blurs)</filter>
        <rect width="20" height="20" filter="url(#blur)"/>
      </svg>
      """#)
    view.frame.size = CGSize(width: 600, height: 600)
    let clock = ContinuousClock()
    let full = try await clock.measure { _ = try await view.takeSnapshot() }
    // Time out a tenth of the way through, and compare with the full time, which depends on the machine.
    view.configuration = SVGUIViewConfiguration(timeoutDuration: full / 10)
    var error: SVGRenderingError?
    let cancelled = await clock.measure {
      do throws(SVGRenderingError) {
        _ = try await view.takeSnapshot()
      } catch let e {
        error = e
      }
    }
    #expect(error == .timedOut)
    #expect(cancelled < full / 2, "Rendering took \(cancelled) after a timeout of \(full / 10), and \(full) in full")
  }

  @Test("cancelling the task that waits for a snapshot stops the rendering in the middle")
  func cancellingSnapshotStopsRendering() async throws {
    let blurs = String(repeating: #"<feGaussianBlur stdDeviation="10"/>"#, count: 10_000)
    let view = makeView(
      #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <filter id="blur">\#(blurs)</filter>
        <rect width="20" height="20" filter="url(#blur)"/>
      </svg>
      """#)
    view.frame.size = CGSize(width: 600, height: 600)
    let clock = ContinuousClock()
    let full = try await clock.measure { _ = try await view.takeSnapshot() }
    // Cancel a tenth of the way through, and compare with the full time, which depends on the machine.
    let start = clock.now
    let task = Task { _ = try await view.takeSnapshot() }
    try await Task.sleep(for: full / 10)
    task.cancel()
    let result = await task.result
    let cancelled = clock.now - start
    #expect(throws: SVGRenderingError.cancelled) { try result.get() }
    #expect(cancelled < full / 2, "Rendering took \(cancelled) with a cancellation after \(full / 10), and \(full) in full")
  }

  @Test(
    "a rendering that timed out or was cancelled keeps the image that the view shows",
    arguments: [SVGRenderingError.timedOut, .cancelled])
  func showKeepsImage(error: SVGRenderingError) throws {
    let view = makeView(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
    let image = try makeImage()
    view.show(.success(image))
    view.show(.failure(error))
    let contents = try #require(view.layer.contents)
    #expect(contents as AnyObject === image)
  }

  @Test(
    "a rendering that has nothing to show clears the image that the view shows",
    arguments: [SVGRenderingError.missingRootElement, .zeroSizedRect])
  func showClearsImage(error: SVGRenderingError) throws {
    let view = makeView(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
    view.show(.success(try makeImage()))
    view.show(.failure(error))
    #expect(view.layer.contents == nil)
  }

  @Test("setting the data that a view displays does not render it again")
  func settingSameDataDoesNotRenderAgain() async throws {
    let view = makeView(Self.square)
    render(view)
    try await waitForImage(in: view, width: 20)
    // Let the view finish the rendering, so that it handles new data at once instead of queueing it.
    try await Task.sleep(for: .milliseconds(100))
    view.data = Data(Self.square.utf8)
    try await Task.sleep(for: .milliseconds(100))
    #expect(!view.layer.needsDisplay())
    view.data = Data(Self.square.replacingOccurrences(of: "<rect", with: "<circle").utf8)
    let deadline = ContinuousClock.now + .seconds(10)
    while !view.layer.needsDisplay() && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(view.layer.needsDisplay(), "New data renders the view again")
  }

  @Test("a view renders again at its new size when its size changes")
  func rendersAgainWhenResized() async throws {
    let view = makeView(Self.square)
    render(view)
    try await waitForImage(in: view, width: 20)
    view.frame.size = CGSize(width: 40, height: 20)
    view.layoutIfNeeded()
    #expect(view.layer.needsDisplay())
    render(view)
    try await waitForImage(in: view, width: 40)
  }

  @Test("a view keeps showing its image until it renders again at its new size")
  func keepsImageWhileRenderingAgain() async throws {
    let view = makeView(Self.square)
    render(view)
    try await waitForImage(in: view, width: 20)
    let image = try #require(view.layer.contents)
    view.frame.size = CGSize(width: 40, height: 20)
    render(view)
    // The rendering for the new size has started but not finished, so that the view does not blink.
    let contents = try #require(view.layer.contents)
    #expect(contents as AnyObject === image as AnyObject)
    try await waitForImage(in: view, width: 40)
  }

  @Test("a new rendering cancels the one in progress")
  func newRenderingCancelsOlderOne() async throws {
    let view = makeView(Self.square)
    render(view)
    let older = try #require(view.renderingTask)
    view.frame.size = CGSize(width: 40, height: 20)
    render(view)
    let newer = try #require(view.renderingTask)
    #expect(older.isCancelled)
    #expect(!newer.isCancelled)
    try await waitForImage(in: view, width: 40)
  }

  @Test("a view does not render again when only its position changes")
  func doesNotRenderAgainWhenMoved() async throws {
    let view = makeView(Self.square)
    render(view)
    try await waitForImage(in: view, width: 20)
    view.frame.origin = CGPoint(x: 10, y: 10)
    view.layoutIfNeeded()
    #expect(!view.layer.needsDisplay())
  }

  @Test("a view renders again when its content mode changes to another one")
  func rendersAgainWhenContentModeChanges() async throws {
    let view = makeView(Self.square)
    view.contentMode = .scaleAspectFit
    render(view)
    try await waitForImage(in: view, width: 20)
    view.contentMode = .scaleAspectFit
    #expect(!view.layer.needsDisplay())
    view.contentMode = .scaleAspectFill
    #expect(view.layer.needsDisplay())
  }

  @Test("a rendering that finishes after a newer one does not replace its image")
  func olderRenderingDoesNotReplaceNewerOne() async throws {
    // Blurring a large bitmap takes much longer than blurring a small one.
    let view = makeView(
      #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <filter id="blur"><feGaussianBlur stdDeviation="5"/></filter>
        <rect width="20" height="20" filter="url(#blur)"/>
      </svg>
      """#)
    view.frame.size = CGSize(width: 1000, height: 1000)
    render(view)
    view.frame.size = CGSize(width: 10, height: 10)
    view.setNeedsDisplay()
    render(view)
    try await waitForImage(in: view, width: 10)
    // Give the older rendering time to finish.
    try await Task.sleep(for: .seconds(2))
    #expect(shownWidth(view) == Int((10 * UIScreen.main.scale).rounded(.up)))
  }

  /// The bytes that malloc has handed out and that are not freed yet.
  private func mallocBytesInUse() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return statistics.size_in_use
  }

  @Test(
    "rendering a filter again and again does not keep using more memory",
    arguments: [
      #"<feGaussianBlur stdDeviation="5"/>"#,
      #"<feFlood flood-color="red" result="flood"/><feGaussianBlur in="flood" stdDeviation="5"/>"#,
      #"<feFlood flood-color="red"/>"#,
      #"<feOffset dx="5" dy="5"/>"#,
      #"<feBlend in="SourceGraphic" in2="SourceGraphic" mode="multiply"/>"#,
      #"<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode/></feMerge>"#,
    ])
  func filterDoesNotLeak(primitives: String) async throws {
    let view = makeView(
      #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <filter id="filter">\#(primitives)</filter>
        <rect width="100" height="100" fill="green" filter="url(#filter)"/>
      </svg>
      """#)
    view.contentMode = .scaleAspectFit
    view.frame.size = CGSize(width: 400, height: 400)
    for _ in 0..<2 { _ = try await view.takeSnapshot() }
    // The footprint of the process does not show the leak in the simulator, so count what malloc hands out.
    let before = mallocBytesInUse()
    let renderings = 100
    for _ in 0..<renderings { _ = try await view.takeSnapshot() }
    let growth = mallocBytesInUse() - before
    // A leak keeps at least one bitmap of the view, which is smaller than the filter region, per rendering.
    // Other tests that run at the same time allocate memory too, so allow for some of them.
    let pixels = (400 * UIScreen.main.scale).rounded(.up)
    let bitmap = Int(pixels * pixels) * 4
    #expect(
      growth < bitmap * renderings / 4,
      "Memory grew by \(growth / 1_048_576) MB over \(renderings) renderings; a bitmap is \(bitmap / 1_048_576) MB")
  }
}
