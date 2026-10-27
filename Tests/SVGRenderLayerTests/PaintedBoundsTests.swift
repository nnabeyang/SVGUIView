import CoreGraphics
import Foundation
import SVGRenderCG
import Testing

@testable import SVGCore
@testable import SVGRenderLayer

/// The render tree of a document with the content, rendered into a rectangle of 100 by 100.
private func tree(_ content: String) async throws -> RenderTree {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  return try #require(
    await RenderTreeBuilder(base: base, viewPort: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1).build(fit: fit))
}

/// What the root of a document with the content paints, in the coordinates of the document.
private func bounds(_ content: String) async throws -> CGRect {
  try #require(try await tree(content).root).paintedBounds
}

@Suite("Painted bounds")
struct PaintedBoundsTests {
  /// Documents, and the rectangles that they paint in.
  private static let documents: [(String, CGRect)] = [
    (#"<rect x="10" y="20" width="30" height="40"/>"#, CGRect(x: 10, y: 20, width: 30, height: 40)),
    // A stroke paints outside the shape, by half its width, and more at a sharp miter. The bounds of the shape grow
    // by half the width too, for text and images, which is more than the stroke of a path needs.
    (
      #"<rect x="10" y="20" width="30" height="40" stroke="black" stroke-width="4"/>"#,
      CGRect(x: 8, y: 18, width: 34, height: 44)
    ),
    (
      #"<path d="M10 50 L50 40 L10 30" fill="none" stroke="black" stroke-width="2" stroke-miterlimit="20"/>"#,
      CGRect(x: 9, y: 29, width: 45.123, height: 22)
    ),
    // A clip path paints nothing outside the shape, so it leaves out the stroke.
    (
      #"<clipPath id="c"><rect width="100" height="100"/></clipPath>"#
        + ##"<rect x="10" y="20" width="30" height="40" stroke="black" stroke-width="4" clip-path="url(#c)"/>"##,
      CGRect(x: 10, y: 20, width: 30, height: 40)
    ),
    // A filter paints in its region, which is larger than the element by 10% on each side by default.
    (
      #"<filter id="f"><feGaussianBlur stdDeviation="1"/></filter>"#
        + ##"<rect x="10" y="20" width="30" height="40" filter="url(#f)"/>"##,
      CGRect(x: 7, y: 16, width: 36, height: 48)
    ),
    // The transforms of the elements move what they paint.
    (
      #"<g transform="translate(10 5)"><rect width="10" height="10" transform="scale(2)"/></g>"#,
      CGRect(x: 10, y: 5, width: 20, height: 20)
    ),
    (#"<rect width="10" height="10"/><rect x="50" y="60" width="10" height="10"/>"#, CGRect(x: 0, y: 0, width: 60, height: 70)),
    (#"<rect width="10" height="10" visibility="hidden"/>"#, .null),
  ]

  @Test("the rectangle that a document paints in", arguments: documents)
  func paintedBounds(content: String, expected: CGRect) async throws {
    let bounds = try await bounds(content)
    if expected.isNull {
      #expect(bounds.isNull)
    } else {
      #expect(abs(bounds.minX - expected.minX) < 0.01 && abs(bounds.minY - expected.minY) < 0.01, "\(bounds)")
      #expect(abs(bounds.width - expected.width) < 0.01 && abs(bounds.height - expected.height) < 0.01, "\(bounds)")
    }
  }

  /// Documents that paint in many ways, past the view box.
  private static let paintings = [
    #"<path d="M-20 50 L50 40 L-20 30" fill="none" stroke="red" stroke-width="6" stroke-miterlimit="20"/>"#,
    #"<line x1="90" y1="10" x2="130" y2="10" stroke="red" stroke-width="8" stroke-linecap="square"/>"#,
    #"<text x="80" y="50" font-size="30" stroke="red" stroke-width="3">Text</text>"#,
    #"<filter id="f"><feGaussianBlur stdDeviation="4"/></filter>"#
      + ##"<rect x="-10" y="-10" width="30" height="30" fill="red" filter="url(#f)"/>"##,
    #"<g transform="rotate(30 50 50)" opacity="0.5"><rect x="60" y="60" width="60" height="20" fill="red"/></g>"#,
    #"<svg x="50" y="50" width="80" height="80" overflow="visible"><circle cx="70" cy="70" r="20" fill="red"/></svg>"#,
    ##"<defs><circle id="c" r="15" fill="red" stroke="red" stroke-width="10"/></defs><use href="#c" x="110" y="-5"/>"##,
  ]

  @Test("a document paints nothing outside the rectangle", arguments: paintings)
  func containsPainting(content: String) async throws {
    let tree = try await tree(content)
    let root = try #require(tree.root)
    let bounds = root.paintedBounds
    // The bitmap shows the coordinates of the document from -100 to 200, one pixel for each unit.
    let size = 300
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    let context = try #require(
      CGContext(
        data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.concatenate(CGAffineTransform(1, 0, 0, -1, 100, CGFloat(size - 100)))
    await CGPainter(scale: 1).paint([root], into: context)
    var outside = 0
    var painted = 0
    for y in 0..<size {
      for x in 0..<size where pixels[(y * size + x) * 4 + 3] > 0 {
        painted += 1
        // The pixel covers the unit square from its corner, and antialiasing can paint a pixel at the edge.
        let unit = CGRect(x: x - 100, y: y - 100, width: 1, height: 1)
        if !bounds.insetBy(dx: -1, dy: -1).contains(unit) { outside += 1 }
      }
    }
    #expect(painted > 0)
    #expect(outside == 0, "\(outside) pixels outside \(bounds)")
  }
}
