import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that elements blend with what's behind them in their isolation groups.
@MainActor
@Suite("Blending")
struct BlendingTests {
  /// A lime square with a yellow square over its right half, with the style.
  private func squares(_ style: String, around: (String, String) = ("", "")) -> String {
    #"<rect width="20" height="20" fill="lime"/>"# + around.0
      + #"<rect x="10" width="10" height="20" fill="yellow" style=""# + style + #""/>"# + around.1
  }

  @Test("multiply makes the product of the colors of an element and of what's behind it")
  func multiply() async throws {
    // Lime times yellow is lime.
    #expect(try await pixel(squares("mix-blend-mode: multiply"), x: 15, y: 10) == [0, 255, 0, 255])
    #expect(try await pixel(squares(""), x: 15, y: 10) == [255, 255, 0, 255])
  }

  @Test("an element blends only with what's in its isolation group")
  func isolation() async throws {
    let isolated = squares("mix-blend-mode: multiply", around: (#"<g style="isolation: isolate">"#, "</g>"))
    #expect(try await pixel(isolated, x: 15, y: 10) == [255, 255, 0, 255])
    let notIsolated = squares("mix-blend-mode: multiply", around: ("<g>", "</g>"))
    #expect(try await pixel(notIsolated, x: 15, y: 10) == [0, 255, 0, 255])
  }

  @Test("an element with an opacity blends that much")
  func opacity() async throws {
    let color = try await pixel(squares("mix-blend-mode: difference; opacity: 0.5"), x: 15, y: 10)
    // Lime minus yellow is red, which covers half of the lime.
    #expect(abs(Int(color[0]) - 128) <= 2 && abs(Int(color[1]) - 128) <= 2 && color[2] == 0, "\(color)")
  }
}
