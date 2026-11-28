import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("Hit testing")
struct HitTestingTests {
  /// A view, by default of 200 by 100, that shows a document of the content, by default in a view box of 200 by 100.
  private func view(
    _ content: String, root: String = #"viewBox="0 0 200 100""#, size: CGSize = CGSize(width: 200, height: 100)
  ) -> SVGUIView {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" \#(root)>"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(origin: .zero, size: size), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  /// The `id` of the frontmost element at the point, or `nil` if there is none.
  private func hit(_ view: SVGUIView, _ x: CGFloat, _ y: CGFloat, tolerance: CGFloat = 0) async -> String? {
    await view.document.element(at: CGPoint(x: x, y: y), tolerance: tolerance)?.attribute("id")
  }

  @Test("the frontmost shape is hit, and every shape at the point from the front")
  func overlapping() async throws {
    let view = view(
      #"<g id="g"><rect id="back" x="10" y="10" width="100" height="80" fill="green"/>"#
        + #"<rect id="front" x="50" y="30" width="100" height="40" fill="orange"/></g>"#)
    #expect(await hit(view, 80, 50) == "front")
    #expect(await hit(view, 20, 50) == "back")
    #expect(await hit(view, 180, 50) == nil)
    let all = await view.document.elements(at: CGPoint(x: 80, y: 50))
    #expect(all.map { $0.attribute("id") } == ["front", "back"])
  }

  @Test("a shape is hit where its fill and its stroke paint, by default")
  func paintedAreas() async throws {
    let view = view(
      #"<path id="ring" fill-rule="evenodd" d="M 10 10 h 80 v 80 h -80 Z M 30 30 h 40 v 40 h -40 Z"/>"#
        + #"<rect id="outline" x="110" y="10" width="80" height="80" fill="none" stroke="black" stroke-width="4"/>"#)
    #expect(await hit(view, 20, 50) == "ring")
    // The hole of the even-odd rule isn't filled.
    #expect(await hit(view, 50, 50) == nil)
    #expect(await hit(view, 111, 50) == "outline")
    // A fill of none isn't hit.
    #expect(await hit(view, 150, 50) == nil)
  }

  @Test("a stroke is hit with its caps and joins, and not in the gaps of its dashes")
  func strokes() async throws {
    let view = view(
      #"<line id="dashed" x1="10" y1="20" x2="190" y2="20" stroke="black" stroke-width="10" stroke-dasharray="20 20"/>"#
        + #"<line id="square" x1="20" y1="50" x2="180" y2="50" stroke="black" stroke-width="10" stroke-linecap="square"/>"#
        + #"<line id="butt" x1="20" y1="80" x2="180" y2="80" stroke="black" stroke-width="10"/>"#)
    #expect(await hit(view, 15, 20) == "dashed")
    #expect(await hit(view, 40, 20) == nil)
    // pathLength scales the dashes: 180 long, 9 makes them 20.
    let scaled = self.view(
      #"<line id="scaled" x1="10" y1="20" x2="190" y2="20" stroke="black" stroke-width="10" stroke-dasharray="1 1" pathLength="9"/>"#)
    #expect(await hit(scaled, 15, 20) == "scaled")
    #expect(await hit(scaled, 40, 20) == nil)
    #expect(await hit(view, 17, 50) == "square")
    #expect(await hit(view, 17, 80) == nil)
  }

  @Test("hidden and invisible shapes aren't hit by default, while transparent and masked ones are")
  func visibility() async throws {
    let view = view(
      #"<mask id="m"><rect width="200" height="100" fill="black"/></mask>"#
        + #"<rect id="hidden" x="0" y="0" width="40" height="40" visibility="hidden"/>"#
        + #"<g display="none"><rect id="none" x="50" y="0" width="40" height="40"/></g>"#
        + #"<rect id="transparent" x="100" y="0" width="40" height="40" opacity="0" fill-opacity="0"/>"#
        + #"<rect id="masked" x="150" y="0" width="40" height="40" mask="url(#m)"/>"#)
    #expect(await hit(view, 20, 20) == nil)
    #expect(await hit(view, 70, 20) == nil)
    #expect(await hit(view, 120, 20) == "transparent")
    #expect(await hit(view, 170, 20) == "masked")
  }

  @Test("a shape isn't hit where its clip path or the clip path of an ancestor clips it out")
  func clipPaths() async throws {
    let view = view(
      #"<clipPath id="c"><circle cx="50" cy="50" r="20"/></clipPath>"#
        + #"<clipPath id="bbox" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>"#
        + #"<rect id="clipped" width="100" height="100" clip-path="url(#c)"/>"#
        + #"<g clip-path="url(#bbox)"><rect id="half" x="120" y="10" width="60" height="80"/></g>"#)
    #expect(await hit(view, 50, 50) == "clipped")
    #expect(await hit(view, 10, 10) == nil)
    #expect(await hit(view, 130, 50) == "half")
    #expect(await hit(view, 170, 50) == nil)
  }

  @Test(
    "pointer-events chooses where a shape is hit",
    arguments: [
      // A hidden shape with a fill of none and a stroke, at its fill and on its stroke.
      ("visiblePainted", nil, nil),
      ("visibleFill", nil, nil),
      ("painted", nil, "s"),
      ("fill", "s", nil),
      ("stroke", nil, "s"),
      ("all", "s", "s"),
      ("none", nil, nil),
      // The bounding box is the object bounding box, without the outer half of the stroke.
      ("bounding-box", "s", nil),
    ] as [(String, String?, String?)])
  func pointerEvents(value: String, atFill: String?, onStroke: String?) async throws {
    let view = view(
      #"<g pointer-events="\#(value)"><rect id="s" x="20" y="20" width="60" height="60" fill="none" stroke="black" stroke-width="4" visibility="hidden"/></g>"#
    )
    #expect(await hit(view, 50, 50) == atFill)
    // Outside the fill, on the stroke.
    #expect(await hit(view, 19, 50) == onStroke)
  }

  @Test("pointer-events of a visible shape, and in a style sheet")
  func visiblePointerEvents() async throws {
    let view = view(
      "<style>.through { pointer-events: none }</style>"
        + #"<rect id="under" width="100" height="100"/>"#
        + #"<rect class="through" id="over" width="100" height="100"/>"#
        + #"<rect id="empty" x="120" y="20" width="60" height="60" fill="none" pointer-events="visibleFill"/>"#)
    #expect(await hit(view, 50, 50) == "under")
    #expect(await hit(view, 150, 50) == "empty")
  }

  @Test("the transforms, the view boxes and the content mode place what's hit")
  func placement() async throws {
    let view = view(
      #"<svg x="100" y="0" width="100" height="100" viewBox="0 0 10 10"><rect id="inner" x="5" y="5" width="5" height="5"/></svg>"#
        + #"<rect id="turned" x="0" y="0" width="40" height="10" transform="translate(50 0) rotate(90)"/>"#)
    #expect(await hit(view, 175, 75) == "inner")
    #expect(await hit(view, 125, 25) == nil)
    #expect(await hit(view, 45, 30) == "turned")
    #expect(await hit(view, 20, 5) == nil)
    // A document of 100 by 50 that fits a view of 200 by 200 is twice as large, 50 points from the top.
    let fitted = self.view(
      #"<rect id="r" width="10" height="10"/>"#, root: #"width="100" height="50""#,
      size: CGSize(width: 200, height: 200))
    fitted.contentMode = .scaleAspectFit
    #expect(await hit(fitted, 15, 65) == "r")
    #expect(await hit(fitted, 15, 15) == nil)
  }

  @Test("the content of a use element is hit as the use element, and the markers of a shape aren't hit")
  func useAndMarkers() async throws {
    let view = view(
      ##"<defs><rect id="shape" width="40" height="40"/><marker id="m" markerWidth="40" markerHeight="40" refX="20" refY="20" markerUnits="userSpaceOnUse"><circle cx="20" cy="20" r="18"/></marker></defs>"##
        + ##"<use id="u" href="#shape" x="10" y="10"/>"##
        + #"<path id="marked" d="M 100 50 L 160 50" stroke="black" stroke-width="2" marker-end="url(#m)"/>"#)
    #expect(await hit(view, 30, 30) == "u")
    #expect(await hit(view, 130, 50) == "marked")
    #expect(await hit(view, 170, 50) == nil)
  }

  @Test("text is hit on the cells of its glyphs, as the text or the span that the glyph is in")
  func text() async throws {
    let view = view(
      #"<text id="t" x="10" y="60" font-size="40">AB<tspan id="ts">CD</tspan></text>"#)
    let text = try #require(view.document.element(id: "t"))
    let box = try #require(await text.boundingBox())
    // Above the glyph of A, inside its cell.
    #expect(await hit(view, 15, box.minY + 2) == "t")
    #expect(await hit(view, box.maxX - 5, box.midY) == "ts")
    #expect(await hit(view, box.maxX + 10, box.midY) == nil)
  }

  @Test("an image is hit over its rectangle, and an element with a filter over its own shape")
  func imagesAndFilters() async throws {
    // A transparent pixel.
    let png =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    let view = view(
      #"<filter id="f"><feOffset dx="50"/></filter>"#
        + #"<image id="i" x="10" y="10" width="40" height="40" href="data:image/png;base64,\#(png)"/>"#
        + #"<rect id="moved" x="110" y="10" width="20" height="20" filter="url(#f)"/>"#)
    #expect(await hit(view, 30, 30) == "i")
    #expect(await hit(view, 120, 20) == "moved")
    #expect(await hit(view, 170, 20) == nil)
  }

  @Test("a tolerance hits a thin line from a distance in points of the view")
  func tolerance() async throws {
    // The document is twice as large as its view box, so the line is 1 point wide.
    let view = view(
      #"<line id="thin" x1="10" y1="25" x2="90" y2="25" stroke="black" stroke-width="0.5"/>"#,
      root: #"viewBox="0 0 100 50""#)
    #expect(await hit(view, 100, 56) == nil)
    #expect(await hit(view, 100, 56, tolerance: 8) == "thin")
    #expect(await hit(view, 100, 70, tolerance: 8) == nil)
  }

  @Test("hit testing reads the changes made just before, and builds its tree again only after a change")
  func changes() async throws {
    let view = view(#"<rect id="r" width="50" height="50"/>"#)
    #expect(await hit(view, 25, 25) == "r")
    #expect(await hit(view, 30, 30) == "r")
    #expect(view.hitTestingTreeCount == 1)
    try #require(view.document.element(id: "r")).setAttribute("x", to: "100")
    #expect(await hit(view, 25, 25) == nil)
    #expect(await hit(view, 125, 25) == "r")
    #expect(view.hitTestingTreeCount == 2)
    // A document that a view doesn't show has no elements at a point.
    let shown = view.document
    await view.setData(Data(document(#"<rect width="10" height="10"/>"#).utf8))
    #expect(await shown.elements(at: CGPoint(x: 5, y: 5)).isEmpty)
  }
}
