import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the fill of text with objectBoundingBox units is painted in the bounds of its glyph cells, which are
/// the bounds of the whole text for its tspans.
@MainActor
@Suite("Text paints")
struct TextPaintTests {
  /// Whether a pixel is mostly red, which the gradients paint where the bounds are the outlines of the glyphs.
  private func isRed(_ pixel: [UInt8]) -> Bool {
    pixel[3] > 64 && Int(pixel[0]) > Int(pixel[1]) + 64 && Int(pixel[0]) > Int(pixel[2]) + 64
  }

  /// Whether the rendering has a red pixel.
  private func hasRed(_ rendering: Rendering) -> Bool {
    stride(from: 0, to: rendering.components.count, by: 4).contains {
      isRed(Array(rendering.components[$0..<($0 + 4)]))
    }
  }

  @Test("the top of the bounds of text is the top of its glyph cells, which is above its glyphs")
  func glyphCellHeight() async throws {
    // Red only in the top twentieth, which the glyph cells have above the outlines of the glyphs.
    let gradient = #"""
      <linearGradient id="g" x2="0" y2="1">
        <stop offset="0.05" stop-color="red"/><stop offset="0.05" stop-color="lime"/>
      </linearGradient>
      """#
    let rendering = try await render(gradient + #"<text x="2" y="16" font-size="16" fill="url(#g)">H</text>"#)
    #expect(rendering.components.contains { $0 > 0 })
    #expect(!hasRed(rendering))
  }

  @Test("an emoji is drawn in its own colors, whatever the color of the fill is")
  func emoji() async throws {
    let rendering = try await render(#"<text x="1" y="16" font-size="16" fill="black">😀</text>"#)
    // A pixel that isn't gray, as the yellow of the face.
    let colored = stride(from: 0, to: rendering.components.count, by: 4).contains { index in
      let pixel = rendering.components[index..<(index + 4)].map(Int.init)
      return pixel[3] > 200 && pixel[0] - pixel[2] > 100
    }
    #expect(colored)
  }

  @Test("the fill of a tspan is painted in the bounds of the whole text")
  func tspanBounds() async throws {
    // Red in the left half of the text, where the tspan isn't.
    let gradient = #"""
      <linearGradient id="g">
        <stop offset="0.5" stop-color="red"/><stop offset="0.5" stop-color="lime"/>
      </linearGradient>
      """#
    let rendering = try await render(
      gradient + #"<text x="1" y="12" font-size="5">HHH<tspan fill="url(#g)">HHH</tspan></text>"#)
    #expect(!hasRed(rendering))
    #expect(rendering.components.enumerated().contains { $0.offset % 4 == 1 && $0.element > 128 })
  }
}
