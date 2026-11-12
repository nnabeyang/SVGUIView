import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests the caps of strokes on subpaths without length.
@MainActor
@Suite("Stroke caps")
struct StrokeCapTests {
  @Test(
    "a square cap of a subpath without length is a square along the x-axis",
    arguments: ["M 10 10 L 10 10", "M 3 3 L 3 3 M 10 10 L 10 10", "M 10 10 L 10 10 L 10 10"])
  func squareCap(d: String) async throws {
    let content = #"<path d=""# + d + #"" stroke="lime" stroke-width="8" stroke-linecap="square"/>"#
    // The corner of the square, which the square turned by 45 degrees doesn't cover.
    #expect(try await pixel(content, x: 6, y: 6) == [0, 255, 0, 255])
    // Above the square, which the square turned by 45 degrees covers.
    #expect(try await pixel(content, x: 9, y: 5) == [0, 0, 0, 0])
  }

  @Test("a moveto alone has no square cap")
  func moveto() async throws {
    let moveto = #"<path d="M 10 10" stroke="lime" stroke-width="8" stroke-linecap="square"/>"#
    #expect(try await pixel(moveto, x: 10, y: 10) == [0, 0, 0, 0])
  }
}
