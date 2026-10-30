import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that strokes are painted with gradients and patterns.
@MainActor
@Suite("Stroke paints")
struct StrokePaintTests {
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

  /// A gradient from red on the left to blue on the right of the document.
  private static let redToBlue = #"""
    <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="20" y2="0">
      <stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>
    </linearGradient>
    """#

  @Test("a stroke with a gradient paints the outline of the stroke with it, and not the inside of the shape")
  func gradient() async throws {
    let content = Self.redToBlue + #"<rect x="2" y="2" width="16" height="16" fill="none" stroke="url(#g)" stroke-width="4"/>"#
    let left = try await pixel(content, x: 2, y: 10)
    let right = try await pixel(content, x: 17, y: 10)
    #expect(left[0] > 200 && left[2] < 60, "\(left)")
    #expect(right[2] > 200 && right[0] < 60, "\(right)")
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }

  @Test("a stroke with a pattern paints the outline of the stroke with it, with the stroke opacity")
  func pattern() async throws {
    let pattern = #"<pattern id="p" patternUnits="userSpaceOnUse" width="20" height="20"><rect width="20" height="20" fill="lime"/></pattern>"#
    let content = pattern + #"<rect x="2" y="2" width="16" height="16" fill="none" stroke="url(#p)" stroke-width="4"/>"#
    #expect(try await pixel(content, x: 2, y: 10) == [0, 255, 0, 255])
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
    let translucent = try await pixel(
      pattern + #"<rect x="2" y="2" width="16" height="16" fill="none" stroke="url(#p)" stroke-width="4" stroke-opacity="0.5"/>"#,
      x: 2, y: 10)
    #expect(abs(Int(translucent[3]) - 128) <= 2, "\(translucent)")
  }

  @Test("the objectBoundingBox of a gradient on a stroke is the bounds of the shape without its stroke")
  func boundingBox() async throws {
    let content = #"""
      <linearGradient id="b"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>
      <rect x="4" y="4" width="12" height="12" fill="none" stroke="url(#b)" stroke-width="8"/>
      """#
    // The left edge of the rectangle is the start of the gradient, which pads the stroke outside it.
    let edge = try await pixel(content, x: 4, y: 10)
    #expect(edge[0] > 230 && edge[2] < 25, "\(edge)")
    #expect(try await pixel(content, x: 1, y: 10) == [255, 0, 0, 255])
  }

  @Test("a fill painted after the stroke covers the inner half of the stroke")
  func strokeFirst() async throws {
    let rect = #"<rect x="4" y="4" width="12" height="12" fill="lime" stroke="blue" stroke-width="4" "#
    // The pixel is inside the rectangle, in the inner half of the stroke.
    let normal = try await pixel(rect + "/>", x: 4, y: 10)
    let strokeFirst = try await pixel(rect + #"paint-order="stroke"/>"#, x: 4, y: 10)
    #expect(normal[2] > 245 && normal[1] < 10, "\(normal)")
    #expect(strokeFirst[1] > 245 && strokeFirst[2] < 10, "\(strokeFirst)")
  }
}
