import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Holds the reading of the files that renderings read until it's opened, and tells when a reading starts.
private final class GatedReading: Sendable {
  private let continuation: AsyncStream<Void>.Continuation
  let started: AsyncStream<Void>
  private let gate = Gate()

  init() {
    (started, continuation) = AsyncStream.makeStream()
  }

  /// Lets the readings that wait, and the ones after them, go on.
  func open() async {
    await gate.open()
  }

  var fetch: @Sendable (URL) async throws -> Data {
    { _ in
      self.continuation.yield()
      await self.gate.wait()
      return Data("#r { fill: lime }".utf8)
    }
  }

  private actor Gate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
      guard !isOpen else { return }
      await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
      isOpen = true
      for waiter in waiters { waiter.resume() }
      waiters = []
    }
  }
}

@MainActor
@Suite("Changes of a view while it renders")
struct ChangesWhileRenderingTests {
  /// A square that a style sheet in another file fills with lime, under a blue square that is hidden, so that a
  /// rendering waits for the reading of the style sheet.
  private static let heldDocument =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"#
    + #"<style>@import url(styles/lime.css);</style><rect id="r" width="20" height="20"/>"#
    + #"<rect id="cover" width="20" height="20" fill="blue" visibility="hidden"/></svg>"#

  /// A view of 20 by 20 that shows the document, whose first rendering has started.
  private func renderingView() -> SVGUIView {
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(Self.heldDocument.utf8),
      baseURL: URL(filePath: "/held/doc.svg"))
    // The changes of the tests are rendered into one image, not as continuous changes.
    view.continuousChangeInterval = .zero
    view.layer.displayIfNeeded()
    return view
  }

  @Test("a change of the document doesn't cancel the rendering in progress, and the view renders it after")
  func documentChange() async throws {
    let reading = GatedReading()
    try await SVGUIView.$resourceFetch.withValue(reading.fetch) {
      let view = renderingView()
      for await _ in reading.started { break }
      let first = try #require(view.renderingTask)
      try #require(view.document.element(id: "cover")).setAttribute("visibility", to: "visible")
      view.layer.displayIfNeeded()
      #expect(!first.isCancelled)
      #expect(view.renderingTask == first)
      #expect(view.isRendering)
      await reading.open()
      try await waitForRendering(of: view)
      #expect(view.renderingTask != first)
      // The blue square shows.
      #expect(green(in: view) == 0)
    }
  }

  @Test("changes of the document while a rendering is in progress are rendered once after it")
  func severalChanges() async throws {
    let reading = GatedReading()
    try await SVGUIView.$resourceFetch.withValue(reading.fetch) {
      let view = renderingView()
      for await _ in reading.started { break }
      let first = view.renderingGeneration
      let cover = try #require(view.document.element(id: "cover"))
      for visibility in ["visible", "hidden", "visible"] {
        cover.setAttribute("visibility", to: visibility)
        view.layer.displayIfNeeded()
      }
      #expect(view.renderingGeneration == first)
      await reading.open()
      try await waitForRendering(of: view)
      #expect(view.renderingGeneration == first + 1)
      #expect(green(in: view) == 0)
    }
  }

  @Test("a display without a change doesn't render again while the view renders")
  func displayWithoutChange() async throws {
    let reading = GatedReading()
    try await SVGUIView.$resourceFetch.withValue(reading.fetch) {
      let view = renderingView()
      for await _ in reading.started { break }
      let first = view.renderingGeneration
      view.setNeedsDisplay()
      view.layer.displayIfNeeded()
      #expect(view.renderingGeneration == first)
      await reading.open()
      try await waitForRendering(of: view)
      #expect(view.renderingGeneration == first)
      // The style sheet fills the square with lime.
      #expect(green(in: view) == 255)
    }
  }

  @Test("a new size cancels the rendering in progress, also after a change of the document")
  func newSize() async throws {
    let reading = GatedReading()
    try await SVGUIView.$resourceFetch.withValue(reading.fetch) {
      let view = renderingView()
      for await _ in reading.started { break }
      let first = try #require(view.renderingTask)
      try #require(view.document.element(id: "cover")).setAttribute("visibility", to: "visible")
      view.frame.size = CGSize(width: 40, height: 40)
      view.layoutIfNeeded()
      view.layer.displayIfNeeded()
      #expect(first.isCancelled)
      let second = try #require(view.renderingTask)
      #expect(second != first)
      #expect(!second.isCancelled)
      await reading.open()
      try await waitForRendering(of: view)
      #expect(green(in: view) == 0)
    }
  }

  @Test("new data cancels the rendering in progress")
  func newData() async throws {
    let reading = GatedReading()
    try await SVGUIView.$resourceFetch.withValue(reading.fetch) {
      let view = renderingView()
      for await _ in reading.started { break }
      let first = try #require(view.renderingTask)
      view.data = Data(document(#"<rect width="20" height="20" fill="blue"/>"#).utf8)
      view.layer.displayIfNeeded()
      #expect(first.isCancelled)
      await reading.open()
      try await waitForRendering(of: view)
      #expect(green(in: view) == 0)
    }
  }
}
