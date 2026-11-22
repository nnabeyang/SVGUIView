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

  @Test("the root element of an SVG image turns about the center of the rectangle of the image")
  func svgImageRootTransform() async throws {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 2" transform="rotate(90)">"#
      + #"<rect width="1" height="2" fill="red"/></svg>"#
    let content =
      #"<image x="5" y="5" width="10" height="10" href="data:image/svg+xml;base64,\#(Data(svg.utf8).base64EncodedString())"/>"#
    let top = try await pixel(content, x: 10, y: 7)
    let bottom = try await pixel(content, x: 10, y: 12)
    #expect(top[0] > 245 && top[3] > 245, "\(top)")
    #expect(bottom[3] < 10, "\(bottom)")
  }

  /// An `<image>` element of an SVG image of the root's attributes and content, with the image's attributes.
  private func svgImage(root: String, content: String, _ attributes: String) -> String {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" "# + root + ">" + content + "</svg>"
    return #"<image href="data:image/svg+xml;base64,\#(Data(svg.utf8).base64EncodedString())" "# + attributes + "/>"
  }

  @Test("an SVG image is placed by the ratio of the width and the height of its root, and its view box is stretched")
  func svgNaturalRatio() async throws {
    // The image of 100 by 100 with a view box of 200 by 100 fills the middle 10 by 10 of the rectangle of 20 by 10.
    let content = svgImage(
      root: #"width="100" height="100" viewBox="0 0 200 100""#,
      content: #"<rect width="200" height="100" fill="green"/>"#, #"y="5" width="20" height="10""#)
    for (x, y) in [(6, 6), (14, 6), (6, 14), (14, 14)] {
      let inside = try await pixel(content, x: x, y: y)
      #expect(inside[1] > 100 && inside[3] > 245, "\(x), \(y): \(inside)")
    }
    for x in [2, 17] {
      let outside = try await pixel(content, x: x, y: 10)
      #expect(outside[3] < 10, "\(x): \(outside)")
    }
  }

  @Test("an SVG image of the ratio of its width and height is sliced to its rectangle by that ratio")
  func svgNaturalRatioSliced() async throws {
    // The square of 20 by 20 is at the top left of the rectangle of 20 by 10, so its top half, the top half of the
    // view box, shows.
    let content = svgImage(
      root: #"width="100" height="100" viewBox="0 0 200 100""#,
      content: #"<rect width="200" height="50" fill="red"/><rect y="50" width="200" height="50" fill="blue"/>"#,
      #"y="5" width="20" height="10" preserveAspectRatio="xMinYMin slice""#)
    for y in [6, 13] {
      let color = try await pixel(content, x: 10, y: y)
      #expect(color[0] > 245 && color[2] < 10 && color[3] > 245, "\(y): \(color)")
    }
    let below = try await pixel(content, x: 10, y: 16)
    #expect(below[3] < 10, "\(below)")
  }

  @Test("an SVG image whose root has the ratio of its view box is placed as before")
  func svgSameRatio() async throws {
    let content = svgImage(
      root: #"width="100" height="100" viewBox="0 0 100 100""#,
      content: #"<rect width="100" height="100" fill="green"/>"#,
      #"y="5" width="20" height="10" preserveAspectRatio="xMinYMid meet""#)
    let inside = try await pixel(content, x: 8, y: 10)
    let outside = try await pixel(content, x: 13, y: 10)
    #expect(inside[1] > 100 && inside[3] > 245, "\(inside)")
    #expect(outside[3] < 10, "\(outside)")
  }

  @Test("the height of an image that has none is the one of the ratio of the width and the height of the SVG root")
  func svgAutoHeight() async throws {
    let content = svgImage(
      root: #"width="100" height="50" viewBox="0 0 100 100""#,
      content: #"<rect width="100" height="100" fill="green"/>"#, #"width="10""#)
    let inside = try await pixel(content, x: 5, y: 3)
    let below = try await pixel(content, x: 5, y: 7)
    #expect(inside[1] > 100 && inside[3] > 245, "\(inside)")
    #expect(below[3] < 10, "\(below)")
  }

  @Test("an image with slice is clipped to its rectangle")
  func sliced() async throws {
    let content = image(#"preserveAspectRatio="xMinYMin slice""#)
    let inside = try await pixel(content, x: 9, y: 5)
    let outside = try await pixel(content, x: 15, y: 5)
    #expect(inside[0] > 245 && inside[3] > 245, "\(inside)")
    #expect(outside[3] < 10, "\(outside)")
  }

  /// An image of a red pixel and a blue pixel, stretched to the user space of 20 by 20, with the attributes.
  private func redAndBlue(_ attributes: String) -> String {
    let png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="
    return #"<image width="20" height="20" preserveAspectRatio="none" href="data:image/png;base64,\#(png)" "#
      + attributes + "/>"
  }

  @Test("a bitmap is interpolated where it's scaled by default")
  func imageRendering() async throws {
    let smooth = try await pixel(redAndBlue(""), x: 9, y: 10)
    #expect(smooth[2] > 20, "\(smooth)")
  }

  @Test("a bitmap isn't interpolated for pixelated, crisp-edges and optimizeSpeed", arguments: ["pixelated", "crisp-edges", "optimizeSpeed"])
  func imageRenderingWithoutInterpolation(value: String) async throws {
    let left = try await pixel(redAndBlue(#"image-rendering="\#(value)""#), x: 9, y: 10)
    let right = try await pixel(redAndBlue(#"image-rendering="\#(value)""#), x: 10, y: 10)
    #expect(left[0] > 245 && left[2] < 10, "\(left)")
    #expect(right[2] > 245 && right[0] < 10, "\(right)")
  }
}
