import CoreGraphics
import Foundation
import SVGRenderCG
import Testing

@testable import SVGCore

/// The alpha values of a black rectangle, by default the square from 30 to 70, in a document of 100 by 100, blurred by
/// a standard deviation, rendered at a scale of 1, a row after another from the top.
private func blurredAlpha(rect: String = #"x="30" y="30" width="40" height="40""#, stdDeviation: String) async throws
  -> [[Int]]
{
  let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
        <feGaussianBlur stdDeviation="\(stdDeviation)"/>
      </filter>
      <rect \(rect) filter="url(#f)"/>
    </svg>
    """
  let base = SVGParser.parse(data: Data(svg.utf8))
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base, viewPort: rect, scale: 1).build(fit: fit))
  var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
  let context = try #require(
    CGContext(
      data: &pixels, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.concatenate(CGAffineTransform(1, 0, 0, -1, 0, 100))
  await CGPainter(scale: 1).paint(tree, into: context)
  return (0..<100).map { y in (0..<100).map { x in Int(pixels[(y * 100 + x) * 4 + 3]) } }
}

/// The standard deviation of the slope of the rising edge in the first 60 of a row of alpha values, which is the
/// standard deviation of the blur of the edge.
private func spread(of alpha: [Int]) -> Double {
  let slope = (0..<60).map { Double(alpha[$0 + 1] - alpha[$0]) }
  let sum = slope.reduce(0, +)
  let mean = slope.indices.reduce(0) { $0 + Double($1) * slope[$1] } / sum
  return sqrt(slope.indices.reduce(0) { $0 + slope[$1] * (Double($1) - mean) * (Double($1) - mean) } / sum)
}

@Suite("Blurring with feGaussianBlur")
struct GaussianBlurTests {
  @Test("different standard deviations blur with all the boxes in both directions")
  func boxesInBothDirections() async throws {
    let alpha = try await blurredAlpha(rect: #"x="25" y="25" width="70" height="70""#, stdDeviation: "10 12")
    // The edge at 25 is blurred about as much as the standard deviation of each direction, while the boxes of one
    // direction without the last would blur it about a fifth less.
    #expect(abs(spread(of: alpha[60]) - 10) < 0.5)
    #expect(abs(spread(of: alpha.map { $0[60] }) - 12) < 0.6)
  }
}
