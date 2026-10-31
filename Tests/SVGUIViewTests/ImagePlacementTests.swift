import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that images, bitmaps and SVG images, are drawn where their `preserveAspectRatio` places them in their
/// rectangles, and not outside the rectangles where their overflow is hidden.
@MainActor
@Suite("Image placement")
struct ImagePlacementTests {
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

  /// A red image of 2 by 1 in the rectangle of 10 by 10 at the origin, with the attributes.
  private func image(_ attributes: String) -> String {
    let png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwH4QBEfcD/ePF9e8AAAAASUVORK5CYII="
    return #"<image width="10" height="10" href="data:image/png;base64,\#(png)" "# + attributes + "/>"
  }

  /// A red SVG image of 2 by 1 in the rectangle of 10 by 10 at the origin, with the attributes.
  private func svgImage(_ attributes: String) -> String {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 1"><rect width="2" height="1" fill="red"/></svg>"#
    let data = Data(svg.utf8).base64EncodedString()
    return #"<image width="10" height="10" href="data:image/svg+xml;base64,\#(data)" "# + attributes + "/>"
  }

  @Test("an SVG image is drawn in the middle of its rectangle by default")
  func svgCentered() async throws {
    let inside = try await pixel(svgImage(""), x: 5, y: 5)
    let above = try await pixel(svgImage(""), x: 5, y: 1)
    #expect(inside[0] > 245 && inside[3] > 245, "\(inside)")
    #expect(above[3] < 10, "\(above)")
  }

  @Test("an SVG image with slice is clipped to its rectangle")
  func svgSliced() async throws {
    let content = svgImage(#"preserveAspectRatio="xMinYMin slice""#)
    let inside = try await pixel(content, x: 9, y: 5)
    let outside = try await pixel(content, x: 15, y: 5)
    #expect(inside[0] > 245 && inside[3] > 245, "\(inside)")
    #expect(outside[3] < 10, "\(outside)")
  }

  @Test("an image with none is stretched to its rectangle")
  func stretched() async throws {
    let content = image(#"preserveAspectRatio="none""#)
    let color = try await pixel(content, x: 5, y: 9)
    #expect(color[0] > 245 && color[3] > 245, "\(color)")
  }

  @Test("an image with meet is in the middle of its rectangle by default")
  func centered() async throws {
    let inside = try await pixel(image(""), x: 5, y: 5)
    let above = try await pixel(image(""), x: 5, y: 1)
    #expect(inside[0] > 245 && inside[3] > 245, "\(inside)")
    #expect(above[3] < 10, "\(above)")
  }

  @Test("an image with slice is clipped to its rectangle")
  func sliced() async throws {
    let content = image(#"preserveAspectRatio="xMinYMin slice""#)
    let inside = try await pixel(content, x: 9, y: 5)
    let outside = try await pixel(content, x: 15, y: 5)
    #expect(inside[0] > 245 && inside[3] > 245, "\(inside)")
    #expect(outside[3] < 10, "\(outside)")
  }
}
