import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests `vector-effect: non-scaling-stroke`, which strokes a shape in the coordinates of the view, as wide as its
/// `stroke-width` there whatever the transforms around it are.
@MainActor
@Suite("Strokes that don't scale")
struct NonScalingStrokeTests {
  /// Whether a pixel of the content rendered in a user space of 20 by 20 is painted.
  private func isPainted(_ rendering: Rendering, x: Int, y: Int) -> Bool {
    rendering.pixel(x: x, y: y)[3] > 0
  }

  @Test("vector-effect takes none and non-scaling-stroke, isn't inherited, and the values that no browser supports are invalid")
  func values() throws {
    let document = SVGUIView(
      data: Data(
        ##"""
        <svg xmlns="http://www.w3.org/2000/svg"><g vector-effect="non-scaling-stroke"><rect id="a"/></g>
        <rect id="b" vector-effect="non-scaling-stroke"/><rect id="c" style="vector-effect: non-scaling-size"/>
        <rect id="d" style="vector-effect: Non-Scaling-Stroke"/></svg>
        """##.utf8)
    ).document
    func value(_ id: String) throws -> String? {
      try #require(document.element(id: id)).computedStyle.property("vector-effect")
    }
    #expect(try value("a") == "none")
    #expect(try value("b") == "non-scaling-stroke")
    #expect(try value("c") == "none")
    #expect(try value("d") == "non-scaling-stroke")
  }

  @Test("the stroke is as wide in the view as stroke-width, under a scale and a scale along one axis")
  func width() async throws {
    // The lines are at y = 10 in the view, 2 wide there, where a stroke that scales would be 8 and 6 wide.
    for transform in ["scale(4)", "translate(0 10) scale(1 3) translate(0 -2.5)"] {
      let rendering = try await render(
        ##"<line x1="0" y1="2.5" x2="5" y2="2.5" stroke="black" stroke-width="2" vector-effect="non-scaling-stroke" "##
          + ##"transform="\##(transform)"/>"##)
      #expect(isPainted(rendering, x: 2, y: 10), "\(transform)")
      #expect(!isPainted(rendering, x: 2, y: 12), "\(transform)")
      #expect(!isPainted(rendering, x: 2, y: 7), "\(transform)")
    }
    // A stroke that scales is wider.
    let scaled = try await render(
      ##"<line x1="0" y1="2.5" x2="5" y2="2.5" stroke="black" stroke-width="2" transform="scale(4)"/>"##)
    #expect(isPainted(scaled, x: 2, y: 12))
  }

  @Test("the dashes are as long in the view as stroke-dasharray")
  func dashes() async throws {
    let rendering = try await render(
      ##"<line x1="0" y1="2.5" x2="5" y2="2.5" stroke="black" stroke-width="2" stroke-dasharray="2 2" "##
        + ##"vector-effect="non-scaling-stroke" transform="scale(4)"/>"##)
    #expect(isPainted(rendering, x: 1, y: 10))
    #expect(!isPainted(rendering, x: 3, y: 10))
    #expect(isPainted(rendering, x: 5, y: 10))
  }

  @Test("a gradient paints the outline of the stroke in the user space")
  func gradient() async throws {
    let rendering = try await render(
      ##"<linearGradient id="g" gradientUnits="userSpaceOnUse" x2="5"><stop offset="0" stop-color="red"/>"##
        + ##"<stop offset="1" stop-color="blue"/></linearGradient>"##
        + ##"<rect x="1" y="1" width="3" height="3" fill="none" stroke="url(#g)" stroke-width="2" "##
        + ##"vector-effect="non-scaling-stroke" transform="scale(4)"/>"##)
    let left = rendering.pixel(x: 4, y: 10)
    let right = rendering.pixel(x: 15, y: 10)
    #expect(left[0] > left[2], "\(left)")
    #expect(right[2] > right[0], "\(right)")
    #expect(!isPainted(rendering, x: 10, y: 10))
    // The stroke is 2 wide in the view, from 3 to 5 at the left edge.
    #expect(!isPainted(rendering, x: 6, y: 10))
  }

  @Test("markers in units of the stroke width scale with the width in the user space")
  func markers() async throws {
    let marker =
      ##"<marker id="m" markerUnits="strokeWidth" markerWidth="1" markerHeight="1" orient="0" overflow="visible">"##
      + ##"<rect width="1" height="1" fill="lime"/></marker>"##
    // The stroke is 4 wide in the view and 1 in the user space, so the marker is 1 by 1 there, and 4 by 4 in the view.
    let rendering = try await render(
      marker
        + ##"<path d="M 1 1 h 1" stroke="none" stroke-width="4" vector-effect="non-scaling-stroke" "##
        + ##"marker-start="url(#m)" transform="scale(4)"/>"##)
    #expect(isPainted(rendering, x: 6, y: 6))
    #expect(!isPainted(rendering, x: 9, y: 9))
  }

  @Test("the stroke is hit where it's painted in the view")
  func hitTesting() async throws {
    let svg =
      ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><line id="l" x1="0" y1="10" x2="25" y2="10" "##
      + ##"stroke="black" stroke-width="4" vector-effect="non-scaling-stroke" transform="scale(4)"/></svg>"##
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    // The line is at y = 40, 4 wide in the view, where a stroke that scales would be 16 wide.
    #expect(await view.document.element(at: CGPoint(x: 50, y: 41))?.attribute("id") == "l")
    #expect(await view.document.element(at: CGPoint(x: 50, y: 46)) == nil)
  }

  @Test("the stroke stays as wide when a change of the document scales the group around it")
  func changes() async throws {
    let svg =
      ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><g id="g" transform="scale(2)">"##
      + ##"<line x1="0" y1="5" x2="10" y2="5" stroke="black" stroke-width="2" vector-effect="non-scaling-stroke"/>"##
      + ##"</g></svg>"##
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    func rendering() async throws -> Rendering {
      let image = try #require(try await view.takeSnapshot().cgImage)
      return Rendering(components: try pixels(of: image), width: image.width, scale: image.width / 20)
    }
    let before = try await rendering()
    #expect(isPainted(before, x: 2, y: 10) && !isPainted(before, x: 2, y: 12))
    let group = try #require(view.document.element(id: "g"))
    group.setAttribute("transform", to: "translate(0 -5) scale(3)")
    let after = try await rendering()
    #expect(isPainted(after, x: 2, y: 10) && !isPainted(after, x: 2, y: 12))
  }
}
