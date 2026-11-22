import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("Hit testing after changes")
struct HitTestingReuseTests {
  private static let size = CGSize(width: 200, height: 100)

  private func view(_ svg: String) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(origin: .zero, size: Self.size), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  /// The `id` attributes of the elements at points of a grid over the view, from the front.
  private func hits(_ view: SVGUIView) async -> [[String?]] {
    var hits = [[String?]]()
    for y in stride(from: 5, to: Self.size.height, by: 10) {
      for x in stride(from: 5, to: Self.size.width, by: 10) {
        hits.append(await view.document.elements(at: CGPoint(x: x, y: y), tolerance: 2).map { $0.attribute("id") })
      }
    }
    return hits
  }

  /// Hit tests the view after a change, and a new view of the document as the view writes it, whose tree is built
  /// without reusing nodes, and expects the same elements at every point.
  private func expectSameHits(
    _ view: SVGUIView, sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let reusing = view.reusingHitTestingTreeCount
    let hits = await hits(view)
    #expect(view.reusingHitTestingTreeCount == reusing + 1, sourceLocation: sourceLocation)
    let fresh = self.view(String(decoding: view.document.svgData(), as: UTF8.self))
    #expect(hits == (await self.hits(fresh)), sourceLocation: sourceLocation)
  }

  private func element(_ id: String, in view: SVGUIView) throws -> SVGDocument.Element {
    try #require(view.document.element(id: id))
  }

  @Test("the elements at points after changes are those of a tree built again")
  func changes() async throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">"#
        + "<style>.big { stroke-width: 12 }</style>"
        + #"<g id="g1"><rect id="a" x="10" y="10" width="40" height="30" fill="teal"/>"#
        + #"<circle id="b" cx="80" cy="30" r="20" fill="orange"/></g>"#
        + #"<g id="g2" transform="translate(0 50)"><rect id="c" x="10" y="0" width="60" height="40" fill="gray"/>"#
        + #"<path id="d" d="M100 10H180" stroke="black" stroke-width="4"/></g></svg>"#)
    _ = await hits(view)
    try element("a", in: view).setAttribute("transform", to: "translate(30 20)")
    try await expectSameHits(view)
    try element("b", in: view).setAttribute("fill", to: "none")
    try await expectSameHits(view)
    try element("d", in: view).setAttribute("class", to: "big")
    try await expectSameHits(view)
    try element("c", in: view).remove()
    try await expectSameHits(view)
    let added = view.document.createElement("rect")
    for (name, value) in [("id", "e"), ("x", "120"), ("y", "20"), ("width", "50"), ("height", "60")] {
      added.setAttribute(name, to: value)
    }
    try element("g1", in: view).insert(added, before: element("a", in: view))
    try await expectSameHits(view)
    // Moving an element to the end of its parent puts it in front.
    try element("g1", in: view).append(element("e", in: view))
    try await expectSameHits(view)
    try #require(try view.document.querySelector("style")).textContent = ".big { stroke-width: 30 }"
    try await expectSameHits(view)
    try element("g2", in: view).setAttribute("transform", to: "translate(20 40)")
    try await expectSameHits(view)
  }

  @Test("a tree reuses no nodes for another size of the view")
  func size() async throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect id="a" width="50" height="50"/></svg>"#)
    _ = await hits(view)
    view.frame.size = CGSize(width: 400, height: 200)
    let reusing = view.reusingHitTestingTreeCount
    #expect(await view.document.element(at: CGPoint(x: 90, y: 90))?.attribute("id") == "a")
    #expect(view.reusingHitTestingTreeCount == reusing)
  }

  @Test("the elements at points at another time of the animations are those of a tree built again")
  func animations() async throws {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">"#
      + #"<rect id="a" x="0" y="10" width="40" height="40"><animate attributeName="x" from="0" to="150" dur="2s"/>"#
      + #"</rect><rect id="b" x="80" y="60" width="40" height="30"/></svg>"#
    let view = view(svg)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .paused)
    _ = await hits(view)
    view.seek(to: .seconds(1))
    try element("b", in: view).setAttribute("x", to: "20")
    let hits = await hits(view)
    let fresh = self.view(String(decoding: view.document.svgData(), as: UTF8.self))
    fresh.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .paused)
    fresh.seek(to: .seconds(1))
    #expect(hits == (await self.hits(fresh)))
  }
}
