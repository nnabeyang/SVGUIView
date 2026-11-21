import CoreGraphics
import Foundation
import SVGRenderCG
import Testing

@testable import SVGCore

/// The alpha values of a document with the content in a viewBox of 100 by 100, rendered into 100 by 100 points at a
/// scale, a row of pixels after another from the top.
func renderedAlpha(_ content: String, scale: CGFloat = 1) async throws -> [[Int]] {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet))
  let tree = try #require(await RenderTreeBuilder(base: base, viewPort: rect, scale: scale).build(fit: fit))
  let side = Int(100 * scale)
  var pixels = [UInt8](repeating: 0, count: side * side * 4)
  let context = try #require(
    CGContext(
      data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, CGFloat(side)))
  await CGPainter(scale: scale).paint(tree, into: context)
  return (0..<side).map { y in (0..<side).map { x in Int(pixels[(y * side + x) * 4 + 3]) } }
}

@Suite("The tiles of patterns")
struct PatternTileScaleTests {
  @Test("a pattern in an enlarged user space is as sharp as the same pattern drawn at its size")
  func enlargedPattern() async throws {
    let enlarged = try await renderedAlpha(
      #"<pattern id="p" patternUnits="userSpaceOnUse" width="2" height="2">"#
        + #"<circle cx="1" cy="1" r="0.8"/></pattern>"#
        + #"<rect transform="scale(10)" width="10" height="10" fill="url(#p)"/>"#)
    let drawn = try await renderedAlpha(
      #"<pattern id="p" patternUnits="userSpaceOnUse" width="20" height="20">"#
        + #"<circle cx="10" cy="10" r="8"/></pattern>"#
        + #"<rect width="100" height="100" fill="url(#p)"/>"#)
    let differences = zip(enlarged.joined(), drawn.joined()).map { abs($0 - $1) }
    #expect(differences.allSatisfy { $0 <= 2 }, "largest \(differences.max() ?? 0)")
  }

  @Test("a tile larger than what shows in a much enlarged user space is no finer than the pixels that show")
  func largeEnlargedTile() async throws {
    // The tile of 1000 by 1000 is enlarged 50 times, and would be 50,000 pixels across at the pixels of the device,
    // too large to be made. Only 100 pixels of it show, so it's made at the scale of the painter.
    let alpha = try await renderedAlpha(
      #"<pattern id="p" patternUnits="userSpaceOnUse" width="1000" height="1000">"#
        + #"<rect width="1000" height="1000"/></pattern>"#
        + #"<rect transform="scale(50)" width="2" height="2" fill="url(#p)"/>"#)
    // The tile is black, and covers the whole rectangle.
    #expect(alpha.joined().allSatisfy { $0 == 255 })
  }

  /// Transforms of a pattern, and the scales of the rectangle that it fills, where a cell of the tile of 1000 by 1000
  /// is much larger than what shows of it: up to 1,000,000 pixels across.
  private static let largeCells: [(String, Int)] = [
    ("", 1000), (#"patternTransform="rotate(90)""#, 50), (#"patternTransform="rotate(90)""#, 1000),
    (#"patternTransform="rotate(30)""#, 50), (#"patternTransform="scale(-1 1)""#, 1000),
    (#"patternTransform="scale(1 -1)""#, 50),
  ]

  @Test("a cell much larger than what shows is drawn, rotated, flipped or not", arguments: largeCells)
  func largeCell(patternTransform: String, scale: Int) async throws {
    let alpha = try await renderedAlpha(
      #"<pattern id="p" patternUnits="userSpaceOnUse" width="1000" height="1000" \#(patternTransform)>"#
        + #"<rect x="-1000" y="-1000" width="3000" height="3000"/></pattern>"#
        + #"<rect transform="scale(\#(scale))" width="\#(100 / scale + 1)" height="\#(100 / scale + 1)" "#
        + #"fill="url(#p)"/>"#)
    // The tile is black, and covers the whole document.
    let transparent = alpha.joined().filter { $0 != 255 }.count
    #expect(transparent == 0, "\(transparent) pixels aren't black")
  }
}
