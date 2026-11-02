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
  /// The red, green, blue and alpha components of a pixel of the rendered document, premultiplied, in its user space
  /// of 20 by 20.
  private func pixel(_ content: String, x: Int, y: Int) async throws -> [UInt8] {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot().cgImage)
    let scale = image.width / 20
    var components = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image,
      in: CGRect(x: -x * scale, y: y * scale - image.height + 1, width: image.width, height: image.height))
    return components
  }

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

  @Test("a result that a later primitive takes by its name has no opacity of its own")
  func namedResult() async throws {
    let content = square(
      #"<feOffset result="a"/><feFlood flood-color="lime"/><feMerge><feMergeNode in="a"/></feMerge>"#,
      attributes: #"opacity="0.5""#)
    let pixel = try await pixel(content, x: 10, y: 10)
    #expect(hasAlpha(pixel, 128), "\(pixel)")
  }
}
