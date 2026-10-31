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

/// The share of a row of pixels from `start` to `end` that is in each pixel after a Gaussian blur of a standard
/// deviation, computed directly.
private func gaussian(from start: Int, to end: Int, deviation: Double) -> [Double] {
  let radius = Int(ceil(deviation * 3))
  let weights = (-radius...radius).map { exp(-Double($0 * $0) / (2 * deviation * deviation)) }
  let sum = weights.reduce(0, +)
  return (0..<100).map { x in
    (-radius...radius).reduce(0) { share, offset in
      (start..<end).contains(x + offset) ? share + weights[offset + radius] / sum : share
    }
  }
}

/// The share of a row of pixels from `start` to `end` that is in each pixel after three centered boxes of a size,
/// with nothing outside the row.
private func boxes(from start: Int, to end: Int, size: Int) -> [Double] {
  var row = (0..<100).map { (start..<end).contains($0) ? 1.0 : 0 }
  for _ in 0..<3 {
    row = (0..<100).map { x in
      (-(size / 2)...(size / 2)).reduce(0) { sum, offset in
        sum + ((0..<100).contains(x + offset) ? row[x + offset] : 0)
      } / Double(size)
    }
  }
  return row
}

/// The standard deviation of the slope of the rising edge in the first 60 of a row of alpha values, which is the
/// standard deviation of the blur of the edge.
private func spread(of alpha: [Int]) -> Double {
  let slope = (0..<60).map { Double(alpha[$0 + 1] - alpha[$0]) }
  let sum = slope.reduce(0, +)
  let mean = slope.indices.reduce(0) { $0 + Double($1) * slope[$1] } / sum
  return sqrt(slope.indices.reduce(0) { $0 + slope[$1] * (Double($1) - mean) * (Double($1) - mean) } / sum)
}

/// The largest difference between alpha values and the shares of an expected blur.
private func difference(_ alpha: [Int], _ expected: [Double]) -> Int {
  zip(alpha, expected).map { abs($0 - Int(($1 * 255).rounded())) }.max() ?? 0
}

@Suite("Blurring with feGaussianBlur")
struct GaussianBlurTests {
  @Test("a small standard deviation blurs with a Gaussian kernel", arguments: [1.0, 2.0, 3.0, 6.0])
  func gaussianKernel(deviation: Double) async throws {
    let alpha = try await blurredAlpha(stdDeviation: "\(deviation)")
    let expected = gaussian(from: 30, to: 70, deviation: deviation)
    var maximum = 0
    for y in 0..<100 {
      maximum = max(maximum, difference(alpha[y], expected.map { $0 * expected[y] }))
    }
    #expect(maximum <= 2)
  }

  @Test("a large standard deviation blurs with three boxes")
  func boxBlurs() async throws {
    let alpha = try await blurredAlpha(stdDeviation: "10")
    // The size of the boxes of the specification, made odd.
    let expected = boxes(from: 30, to: 70, size: 19)
    var maximum = 0
    for y in 0..<100 {
      maximum = max(maximum, difference(alpha[y], expected.map { $0 * expected[y] }))
    }
    #expect(maximum <= 3)
  }

  @Test(
    "a blur of the whole filter region has transparent black outside the region, with a Gaussian kernel or boxes",
    arguments: [(2.0, nil), (10.0, 19)] as [(Double, Int?)])
  func edges(deviation: Double, boxSize: Int?) async throws {
    let alpha = try await blurredAlpha(rect: #"width="100" height="100""#, stdDeviation: "\(deviation)")
    let expected =
      boxSize.map { boxes(from: 0, to: 100, size: $0) } ?? gaussian(from: 0, to: 100, deviation: deviation)
    var maximum = 0
    for y in 0..<100 {
      maximum = max(maximum, difference(alpha[y], expected.map { $0 * expected[y] }))
    }
    #expect(maximum <= 3)
    #expect(alpha[50][0] < 200)
  }

  @Test("a standard deviation of 0 doesn't blur in its direction")
  func zero() async throws {
    let alpha = try await blurredAlpha(stdDeviation: "5 0")
    let expected = gaussian(from: 30, to: 70, deviation: 5)
    for y in 0..<100 {
      let inside = (30..<70).contains(y)
      #expect(difference(alpha[y], expected.map { inside ? $0 : 0 }) <= 2)
    }
  }

  @Test("each direction of different standard deviations blurs with a Gaussian kernel or three boxes")
  func mixed() async throws {
    let alpha = try await blurredAlpha(rect: #"x="30" y="5" width="40" height="90""#, stdDeviation: "2 10")
    // The middle row is far enough from the top and the bottom that the boxes don't change it.
    #expect(difference(alpha[50], gaussian(from: 30, to: 70, deviation: 2)) <= 2)
    // The boxes blur the top edge farther than a Gaussian kernel of 2 would.
    let column = alpha.map { $0[50] }
    #expect((100...155).contains(column[5]))
    #expect(column[13] < 240)
  }

  @Test("different standard deviations blur with all the boxes in both directions")
  func boxesInBothDirections() async throws {
    let alpha = try await blurredAlpha(rect: #"x="25" y="25" width="70" height="70""#, stdDeviation: "10 12")
    // The edge at 25 is blurred about as much as the standard deviation of each direction, while the boxes of one
    // direction without the last would blur it about a fifth less.
    #expect(abs(spread(of: alpha[60]) - 10) < 0.5)
    #expect(abs(spread(of: alpha.map { $0[60] }) - 12) < 0.6)
  }
}
