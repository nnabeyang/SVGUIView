import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the opacity of an element with a filter applies to the result of the filter, once.
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

  @Test("a result that a later primitive takes by its name has no opacity of its own")
  func namedResult() async throws {
    let content = square(
      #"<feOffset result="a"/><feFlood flood-color="lime"/><feMerge><feMergeNode in="a"/></feMerge>"#,
      attributes: #"opacity="0.5""#)
    let pixel = try await pixel(content, x: 10, y: 10)
    #expect(hasAlpha(pixel, 128), "\(pixel)")
  }
}
