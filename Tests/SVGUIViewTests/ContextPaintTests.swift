import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests `context-fill` and `context-stroke`, which paint with the fill and the stroke of the shape that references a
/// marker, or of the `<use>` element that shows an element.
@MainActor
@Suite("Context paints")
struct ContextPaintTests {
  /// A horizontal gradient from red to blue across the bounding box.
  private static let gradient =
    ##"<linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>"##

  @Test("the content of a marker paints with the paints of the shape, at its own opacity")
  func markers() async throws {
    let rendering = try await render(
      ##"<marker id="m" markerWidth="10" markerHeight="10" markerUnits="userSpaceOnUse">"##
        + ##"<rect width="10" height="5" fill="context-stroke" fill-opacity="1"/>"##
        + ##"<rect y="5" width="10" height="5" fill="context-fill" stroke="none"/></marker>"##
        + ##"<path d="M 0 0 h 1" fill="lime" stroke="blue" stroke-opacity="0.2" marker-start="url(#m)"/>"##)
    #expect(rendering.pixel(x: 5, y: 2) == [0, 0, 255, 255])
    #expect(rendering.pixel(x: 5, y: 7) == [0, 255, 0, 255])
  }

  @Test("the copy of an element paints with the paints of the use element, and currentcolor is its own color")
  func useElements() async throws {
    let rendering = try await render(
      ##"<defs><g id="c" color="lime"><rect width="10" height="20" fill="context-fill"/>"##
        + ##"<rect x="10" width="10" height="20" fill="context-stroke" stroke="none"/></g></defs>"##
        + ##"<use href="#c" fill="currentcolor" stroke="blue" color="red"/>"##)
    #expect(rendering.pixel(x: 5, y: 10) == [0, 255, 0, 255])
    #expect(rendering.pixel(x: 15, y: 10) == [0, 0, 255, 255])
  }

  @Test("an element without a context element, or whose context element doesn't paint, paints nothing")
  func withoutContext() async throws {
    #expect(try await pixel(##"<rect width="20" height="20" fill="context-fill"/>"##, x: 10, y: 10) == [0, 0, 0, 0])
    #expect(
      try await pixel(
        ##"<defs><rect id="r" width="20" height="20" fill="context-stroke"/></defs><use href="#r" fill="red"/>"##,
        x: 10, y: 10) == [0, 0, 0, 0])
  }

  @Test("the nearest use element is the context element, and a context paint of a context element is its own")
  func nesting() async throws {
    let rendering = try await render(
      ##"<defs><rect id="r" width="10" height="20" fill="context-fill"/>"##
        + ##"<g id="inner"><use href="#r" fill="blue"/><use href="#r" x="10" fill="context-fill"/></g>"##
        + ##"<marker id="n" markerWidth="4" markerHeight="4" markerUnits="userSpaceOnUse">"##
        + ##"<rect width="4" height="4" fill="context-fill"/></marker>"##
        + ##"<marker id="m" markerWidth="20" markerHeight="20" markerUnits="userSpaceOnUse" refY="10">"##
        + ##"<path d="M 0 0 h 1" fill="context-stroke" marker-start="url(#n)"/></marker></defs>"##
        + ##"<use href="#inner" fill="lime"/>"##
        + ##"<path d="M 0 10 h 1" stroke="red" marker-start="url(#m)"/>"##)
    #expect(rendering.pixel(x: 5, y: 15) == [0, 0, 255, 255])
    #expect(rendering.pixel(x: 15, y: 15) == [0, 255, 0, 255])
    // The inner marker paints the fill of the path in the outer marker, which is the stroke of the shape.
    #expect(rendering.pixel(x: 2, y: 2) == [255, 0, 0, 255])
  }

  @Test("a gradient of the context element paints in its bounding box and user space, across the elements")
  func gradients() async throws {
    let rendering = try await render(
      Self.gradient
        + ##"<defs><g id="c"><rect width="10" height="20" fill="context-fill"/>"##
        + ##"<rect width="10" height="20" fill="context-fill" transform="translate(10 0)"/></g></defs>"##
        + ##"<use href="#c" fill="url(#g)"/>"##)
    // Each rectangle would go from red to blue in its own bounding box.
    let left = rendering.pixel(x: 0, y: 10)
    let middle = rendering.pixel(x: 9, y: 10)
    let right = rendering.pixel(x: 19, y: 10)
    #expect(left[0] > 230 && left[2] < 25, "\(left)")
    #expect(middle[0] > 110 && middle[0] < 145, "\(middle)")
    #expect(right[2] > 230 && right[0] < 25, "\(right)")
  }

  @Test("a gradient of a shape continues into its markers")
  func markerGradients() async throws {
    let rendering = try await render(
      Self.gradient
        + ##"<marker id="m" markerWidth="10" markerHeight="20" markerUnits="userSpaceOnUse" refX="5" refY="20">"##
        + ##"<rect width="10" height="20" fill="context-fill"/></marker>"##
        + ##"<path d="M 15 0 v 20 h -10" fill="url(#g)" stroke="none" marker-end="url(#m)"/>"##)
    // The marker covers x from 0 to 10 of the bounding box from 5 to 15 of the path, and the gradient is padded
    // before 5. At 9, it's about 0.4 of the way, where the bounding box of the marker would make it 0.9.
    let left = rendering.pixel(x: 1, y: 10)
    let middle = rendering.pixel(x: 9, y: 19)
    #expect(left[0] > 230 && left[2] < 25, "\(left)")
    #expect(middle[0] > 130 && middle[0] < 165, "\(middle)")
  }

  @Test("a pattern of a use element in units of its bounding box paints its copy")
  func patterns() async throws {
    let rendering = try await render(
      ##"<pattern id="p" width="0.5" height="1" patternContentUnits="objectBoundingBox">"##
        + ##"<rect width="0.25" height="1" fill="blue"/></pattern>"##
        + ##"<defs><g id="c"><rect width="20" height="20" fill="context-fill"/></g></defs>"##
        + ##"<use href="#c" fill="url(#p)"/>"##)
    #expect(rendering.pixel(x: 2, y: 10) == [0, 0, 255, 255])
    #expect(rendering.pixel(x: 7, y: 10) == [0, 0, 0, 0])
    #expect(rendering.pixel(x: 12, y: 10) == [0, 0, 255, 255])
  }
}
