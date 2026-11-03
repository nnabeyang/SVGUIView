import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a document tells the time after which it looks the same.
@MainActor
@Suite("Animation end")
struct AnimationEndTests {
  /// A view of a document of 20 by 20 with the content, which doesn't play its animations, and waits for its
  /// renderings as long as the other tests do.
  private func makeView(_ content: String) -> SVGUIView {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  /// Documents, and the times after which they look the same, or `nil` for animations that don't end.
  nonisolated private static let documents: [(String, Duration?)] = [
    (#"<rect width="10" height="10"/>"#, .zero),
    (
      "<style>@keyframes a { to { opacity: 0 } } rect { animation: a 2s 1s }</style>"
        + #"<rect width="10" height="10"/>"#,
      .seconds(3)
    ),
    (#"<rect width="10" height="10"><animate attributeName="x" to="10" begin="0.5s" dur="2s"/></rect>"#, .seconds(2.5)),
    (
      "<style>@keyframes a { to { opacity: 0 } } rect { animation: a 2s infinite }</style>"
        + #"<rect width="10" height="10"/>"#,
      nil
    ),
    (#"<rect width="10" height="10"><animate attributeName="x" to="10" dur="2s" repeatCount="indefinite"/></rect>"#, nil),
    // A paused animation stays where it is.
    (
      "<style>@keyframes a { to { opacity: 0 } } rect { animation: a 2s paused }</style>"
        + #"<rect width="10" height="10"/>"#,
      .zero
    ),
  ]

  @Test("the time is zero without animations, the end of the animations that end, and nil for ones that don't", arguments: documents)
  func animationEnd(content: String, expected: Duration?) {
    // The document holds the view weakly, so the test keeps the view.
    let view = makeView(content)
    #expect(view.document.animationEnd == expected)
  }

  @Test("the time includes a change that the view hasn't rendered yet")
  func unrenderedChange() throws {
    let view = makeView(
      "<style>@keyframes a { to { opacity: 0 } } .on { animation: a 1.5s }</style>" + #"<rect id="r" width="10" height="10"/>"#)
    #expect(view.document.animationEnd == .zero)
    try #require(view.document.element(id: "r")).classList.add("on")
    // The view that doesn't play its animations displays time zero, where the change starts the animation.
    #expect(view.document.animationEnd == .seconds(1.5))
  }

  @Test("the time is zero for a document that the view no longer shows")
  func replacedDocument() {
    let view = makeView(#"<rect width="10" height="10"><animate attributeName="x" to="10" dur="2s"/></rect>"#)
    let document = view.document
    #expect(document.animationEnd == .seconds(2))
    view.data = Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)
    #expect(document.animationEnd == .zero)
  }
}
