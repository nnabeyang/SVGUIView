import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests the caps of strokes on subpaths without length.
@MainActor
@Suite("Stroke caps")
struct StrokeCapTests {
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

  @Test("a square cap of a subpath without length is a square along the x-axis, and a moveto alone has no cap")
  func squareCap() async throws {
    for d in ["M 10 10 L 10 10", "M 3 3 L 3 3 M 10 10 L 10 10", "M 10 10 L 10 10 L 10 10"] {
      let content = #"<path d=""# + d + #"" stroke="lime" stroke-width="8" stroke-linecap="square"/>"#
      // The corner of the square, which the square turned by 45 degrees doesn't cover.
      #expect(try await pixel(content, x: 6, y: 6) == [0, 255, 0, 255], "\(d)")
      // Above the square, which the square turned by 45 degrees covers.
      #expect(try await pixel(content, x: 9, y: 5) == [0, 0, 0, 0], "\(d)")
    }
    let moveto = #"<path d="M 10 10" stroke="lime" stroke-width="8" stroke-linecap="square"/>"#
    #expect(try await pixel(moveto, x: 10, y: 10) == [0, 0, 0, 0])
  }
}
