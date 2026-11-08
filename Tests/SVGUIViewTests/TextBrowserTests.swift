import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that text is drawn as Chrome and Firefox draw it where the specifications leave it to user agents.
@MainActor
@Suite("Text as browsers draw it")
struct TextBrowserTests {
  /// The columns of the opaque pixels whose color a test passes, in pixels.
  private func columns(of rendering: Rendering, where test: ([UInt8]) -> Bool) -> [Int] {
    var columns = [Int]()
    for index in stride(from: 0, to: rendering.components.count, by: 4) {
      let pixel = Array(rendering.components[index..<(index + 4)])
      if pixel[3] > 128, test(pixel) { columns.append(index / 4 % rendering.width) }
    }
    return columns
  }

  private func isRed(_ pixel: [UInt8]) -> Bool { Int(pixel[0]) > Int(pixel[1]) + 64 }
  private func isGreen(_ pixel: [UInt8]) -> Bool { Int(pixel[1]) > Int(pixel[0]) + 64 }

  @Test(
    "in vertical text, the underline is on the right of the line and the overline on its left",
    arguments: [("underline", true), ("overline", false)])
  func verticalLines(line: String, isRight: Bool) async throws {
    // Spaces that have no outlines, so that only the line is drawn.
    let rendering = try await render(
      #"<text x="10" y="2" font-size="8" writing-mode="tb" xml:space="preserve" text-decoration="\#(line)">"#
        + "\u{A0}\u{A0}</text>")
    let drawn = columns(of: rendering) { _ in true }
    try #require(!drawn.isEmpty)
    let middle = 10 * rendering.scale
    if isRight {
      #expect(drawn.allSatisfy { $0 > middle })
    } else {
      #expect(drawn.allSatisfy { $0 < middle })
    }
  }

  @Test("a gradient of glyphs that rotate turns isn't turned with them")
  func turnedGlyphPaint() async throws {
    // Red left of x = 10 and green right of it, in the user space.
    let gradient = #"""
      <linearGradient id="g" gradientUnits="userSpaceOnUse" x2="20">
        <stop offset="0.5" stop-color="red"/><stop offset="0.5" stop-color="lime"/>
      </linearGradient>
      """#
    let rendering = try await render(
      gradient + #"<text x="4" y="14" font-size="14" rotate="60" fill="url(#g)">H</text>"#)
    let middle = 10 * rendering.scale
    let red = columns(of: rendering, where: isRed)
    let green = columns(of: rendering, where: isGreen)
    try #require(!red.isEmpty && !green.isEmpty)
    #expect(red.allSatisfy { $0 <= middle + 1 })
    #expect(green.allSatisfy { $0 >= middle - 1 })
  }

}
