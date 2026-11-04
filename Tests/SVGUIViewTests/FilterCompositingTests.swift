import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the clip path, the mask and the opacity of an element with a filter apply to the result of the filter,
/// in this order.
@MainActor
@Suite("Filter compositing")
struct FilterCompositingTests {
  /// A blue square of the whole document with the attributes and a filter of the primitives, whose region is the
  /// document.
  private func square(_ primitives: String, attributes: String = "") -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect width="20" height="20" fill="blue" filter="url(#f)" "# + attributes + "/>"
  }

  /// Whether the alpha of a pixel is within 2 of the expected one.
  private func hasAlpha(_ pixel: [UInt8], _ alpha: Int) -> Bool {
    abs(Int(pixel[3]) - alpha) <= 2
  }

  @Test(
    "the opacity of the element applies once to the result of the filter, however many primitives it has",
    arguments: [
      #"<feOffset/>"#,
      #"<feOffset/><feOffset/>"#,
      #"<feColorMatrix type="identity"/><feOffset/><feGaussianBlur stdDeviation="0"/>"#,
      #"<feFlood flood-color="blue"/><feComposite in2="SourceGraphic"/>"#,
    ])
  func opacity(primitives: String) async throws {
    let pixel = try await pixel(square(primitives, attributes: #"opacity="0.5""#), x: 10, y: 10)
    #expect(hasAlpha(pixel, 128), "\(pixel)")
  }

  @Test(
    "the clip path and the mask of the element apply to the result of the filter, which they cut at their edges",
    arguments: [
      #"<clipPath id="e"><rect x="5" y="5" width="10" height="10"/></clipPath>"#,
      #"<mask id="e"><rect x="5" y="5" width="10" height="10" fill="white"/></mask>"#,
    ])
  func clipAndMask(effect: String) async throws {
    let attribute = effect.hasPrefix("<clipPath") ? #"clip-path="url(#e)""# : #"mask="url(#e)""#
    let content = effect + square(#"<feGaussianBlur stdDeviation="2"/>"#, attributes: attribute)
    // The blur of the whole square is opaque at the edge of the clip, and nothing shows past it.
    let inside = try await pixel(content, x: 5, y: 10)
    #expect(Int(inside[3]) > 240, "\(inside)")
    #expect(try await pixel(content, x: 4, y: 10) == [0, 0, 0, 0])
  }

  @Test(
    "the result of the filter shows past the bounds of the element where the clip path and the mask cover it",
    arguments: [
      #"<clipPath id="e"><rect width="20" height="20"/></clipPath>"#,
      #"<mask id="e" maskUnits="userSpaceOnUse" x="0" y="0" width="20" height="20"><rect width="20" height="20" fill="white"/></mask>"#,
    ])
  func pastBounds(effect: String) async throws {
    let attribute = effect.hasPrefix("<clipPath") ? #"clip-path="url(#e)""# : #"mask="url(#e)""#
    let content =
      effect
      + #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20"><feGaussianBlur stdDeviation="2"/></filter>"#
      + #"<rect x="5" y="5" width="10" height="10" fill="blue" filter="url(#f)" "# + attribute + "/>"
    let outside = try await pixel(content, x: 3, y: 10)
    #expect(Int(outside[3]) > 16, "\(outside)")
  }

  @Test("the filter of an svg element moves its content in the coordinates of the content, which its viewBox scales")
  func viewportOffset() async throws {
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="10" height="10"><feOffset dx="2"/></filter>"#
      + #"<svg width="20" height="20" viewBox="0 0 10 10" filter="url(#f)"><rect width="2" height="10" fill="blue"/></svg>"#
    // The square from 0 to 4 moves by 4.
    #expect(try await pixel(content, x: 7, y: 10) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 3, y: 10) == [0, 0, 0, 0])
  }

  @Test("the filter region in the user space of an svg element is in the coordinates of its content")
  func viewportRegion() async throws {
    // The content is from 0 to 6 in its coordinates, out of the region from 10 to 20.
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="10" width="20" height="10"><feOffset/></filter>"#
      + #"<svg x="2" y="12" width="8" height="8" filter="url(#f)"><rect width="6" height="6" fill="blue"/></svg>"#
    #expect(try await pixel(content, x: 4, y: 14) == [0, 0, 0, 0])
  }

  @Test("the clip path of an svg element with a filter clips the result in the coordinates of its content")
  func viewportClip() async throws {
    // The clip from 0 to 5 in the content is from 0 to 10 in the document, and the blur shows nothing past it.
    let content =
      #"<clipPath id="c"><rect width="5" height="10"/></clipPath><filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="10" height="10">"#
      + #"<feGaussianBlur stdDeviation="1"/></filter><svg width="20" height="20" viewBox="0 0 10 10" clip-path="url(#c)" filter="url(#f)">"#
      + #"<rect width="10" height="10" fill="blue"/></svg>"#
    let inside = try await pixel(content, x: 9, y: 10)
    #expect(Int(inside[3]) > 240, "\(inside)")
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }

  @Test("a result that a later primitive takes by its name has no opacity of its own")
  func namedResult() async throws {
    let content = square(
      #"<feOffset result="a"/><feFlood flood-color="lime"/><feMerge><feMergeNode in="a"/></feMerge>"#,
      attributes: #"opacity="0.5""#)
    let pixel = try await pixel(content, x: 10, y: 10)
    #expect(hasAlpha(pixel, 128), "\(pixel)")
  }
}
