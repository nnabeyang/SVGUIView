import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("Waiting until the view shows the changes")
struct DisplayWaitTests {
  /// A view that has shown a document of a green square, whose changes are continuous if `continuous` is `true`.
  private func makeView(continuous: Bool = false) async throws -> SVGUIView {
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 20, height: 20),
      data: Data(document(##"<rect id="r" width="20" height="20" fill="#00ff00"/>"##).utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    view.continuousChangeInterval = continuous ? .seconds(600) : .zero
    view.layer.displayIfNeeded()
    try await waitForRendering(of: view)
    return view
  }

  /// A task that waits until the view shows the changes, and tells whether it has returned.
  @MainActor
  private final class Waiter {
    private(set) var returned = false
    private(set) var task: Task<Void, Never>?

    init(_ view: SVGUIView) {
      task = Task { @MainActor [weak self] in
        await view.waitUntilDisplayed()
        self?.returned = true
      }
    }
  }

  /// Lets the tasks on the main actor run for a while.
  private func yield() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }

  @Test("waiting returns once the view shows the change, and not before")
  func change() async throws {
    let view = try await makeView()
    try #require(view.document.element(id: "r")).setAttribute("fill", to: "#000000")
    let waiter = Waiter(view)
    await yield()
    #expect(!waiter.returned)
    view.layer.displayIfNeeded()
    await waiter.task?.value
    #expect(green(in: view) == 0)
  }

  @Test("waiting returns at once when the view shows every change")
  func noChange() async throws {
    let view = try await makeView()
    await view.waitUntilDisplayed()
    #expect(view.displayWaiters.isEmpty)
  }

  @Test("waiting returns once the view shows the changes in layers, while the document changes continuously")
  func continuousChanges() async throws {
    let view = try await makeView(continuous: true)
    let rect = try #require(view.document.element(id: "r"))
    for value in [0x40, 0x80, 0x00] {
      rect.setAttribute("fill", to: "#00" + String(format: "%02x", value) + "00")
      let waiter = Waiter(view)
      view.layer.displayIfNeeded()
      await waiter.task?.value
      #expect(green(in: view) == UInt8(value))
    }
    #expect(view.isChangingContinuously)
  }

  @Test("a change made while the view renders an earlier one waits for the rendering after it")
  func changeWhileRendering() async throws {
    let view = try await makeView(continuous: true)
    let rect = try #require(view.document.element(id: "r"))
    rect.setAttribute("fill", to: "#004000")
    view.layer.displayIfNeeded()
    #expect(view.isRendering)
    rect.setAttribute("fill", to: "#000000")
    let waiter = Waiter(view)
    view.layer.displayIfNeeded()
    await waiter.task?.value
    #expect(green(in: view) == 0)
  }

  @Test("waiting returns when the rendering of the change fails")
  func failure() async throws {
    let view = try await makeView()
    try #require(view.document.element(id: "r")).setAttribute("fill", to: "#000000")
    let waiter = Waiter(view)
    await yield()
    // A view without a pixel can't render the document.
    view.frame = .zero
    view.layer.displayIfNeeded()
    await waiter.task?.value
    #expect(view.displayWaiters.isEmpty)
  }

  @Test("waiting returns when new data replaces the document")
  func newData() async throws {
    let view = try await makeView()
    try #require(view.document.element(id: "r")).setAttribute("fill", to: "#000000")
    let waiter = Waiter(view)
    await yield()
    view.data = Data(document("").utf8)
    await waiter.task?.value
    #expect(view.displayWaiters.isEmpty)
  }

  @Test("waiting returns when the task is cancelled")
  func cancellation() async throws {
    let view = try await makeView()
    try #require(view.document.element(id: "r")).setAttribute("fill", to: "#000000")
    let waiter = Waiter(view)
    await yield()
    waiter.task?.cancel()
    await waiter.task?.value
    #expect(view.displayWaiters.isEmpty)
  }
}
