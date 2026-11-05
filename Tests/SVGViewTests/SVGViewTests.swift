import SVGUIView
import SwiftUI
import Testing
import UIKit

@testable import SVGView

@MainActor
@Suite("SVGView")
struct SVGViewTests {
  /// A document whose size is 200 × 200 points, from its view box.
  private static let document = Data(
    #"<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg"><rect width="200" height="200"/></svg>"#.utf8)

  /// Lays out a SwiftUI view in a window and returns the size of the SVGUIView in it, after it shows its data, which
  /// it parses off the main actor. SwiftUI makes the views of a representable only in a window.
  private func sizeOfSVGUIView(in rootView: some View) async throws -> CGSize {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
    window.rootViewController = UIHostingController(rootView: rootView)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    window.layoutIfNeeded()
    let view = try #require(Self.svgUIView(in: window))
    let deadline = ContinuousClock.now + .seconds(10)
    while view.data.isEmpty, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    window.layoutIfNeeded()
    return view.bounds.size
  }

  private static func svgUIView(in view: UIView) -> SVGUIView? {
    if let view = view as? SVGUIView { return view }
    return view.subviews.lazy.compactMap(svgUIView(in:)).first
  }

  @Test("a view takes the size of a frame smaller or larger than its document", arguments: [CGFloat(80), 150, 300])
  func takesFrameSize(side: CGFloat) async throws {
    let size = try await sizeOfSVGUIView(in: SVGView(data: Self.document).frame(width: side, height: side))
    #expect(size == CGSize(width: side, height: side))
  }

  @Test("a view without a proposed size takes the size of its document")
  func takesDocumentSizeWithoutProposal() async throws {
    let size = try await sizeOfSVGUIView(in: SVGView(data: Self.document).fixedSize())
    #expect(size == CGSize(width: 200, height: 200))
  }

  @Test("the content that the view loads last is shown, and loading the same content again does nothing")
  func loadsLatestContent() async throws {
    let coordinator = SVGView.Coordinator()
    let uiView = SVGUIView()
    let other = Data(#"<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"/>"#.utf8)
    coordinator.load(.data(other), into: uiView)
    let first = try #require(coordinator.task)
    coordinator.load(.data(Self.document), into: uiView)
    let second = try #require(coordinator.task)
    await first.value
    await second.value
    #expect(uiView.data == Self.document)
    coordinator.load(.data(Self.document), into: uiView)
    #expect(coordinator.task == second)
  }

  @Test("a file is read off the main actor, and isn't read again for the same URL")
  func readsFile() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).svg")
    try Self.document.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let coordinator = SVGView.Coordinator()
    let uiView = SVGUIView()
    coordinator.load(.file(url), into: uiView)
    let task = try #require(coordinator.task)
    await task.value
    #expect(uiView.data == Self.document)
    try Data().write(to: url)
    coordinator.load(.file(url), into: uiView)
    #expect(coordinator.task == task)
    #expect(uiView.data == Self.document)
  }
}
