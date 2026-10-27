import CoreGraphics
import Foundation
import QuartzCore
import SVGRenderCG
import Testing

@testable import SVGCore
@testable import SVGRenderLayer

/// The size of the renderings in points.
private let size = CGSize(width: 100, height: 100)

/// A bitmap of premultiplied RGBA pixels of the size at the scale, whose first row is the top.
private func bitmap(scale: CGFloat) throws -> CGContext {
  let context = try #require(
    CGContext(
      data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, CGFloat(context.height)))
  return context
}

/// The pixels of a bitmap.
private func pixels(of context: CGContext) -> [UInt8] {
  guard let data = context.data else { return [] }
  return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: context.bytesPerRow * context.height))
}

/// A document with the content at the time, rendered into one bitmap and into layers.
@MainActor
private func renderings(_ content: String, at time: Double, scale: CGFloat) async throws -> (
  bitmap: [UInt8], layers: [UInt8]
) {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let rect = CGRect(origin: .zero, size: size)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(
    await RenderTreeBuilder(base: base.at(time: time), viewPort: rect, scale: scale).build(fit: fit))

  let single = try bitmap(scale: scale)
  await CGPainter(scale: scale).paint(tree, into: single)

  let plan = LayerPlanner(promoted: base.elementsWithAnimatedCompositing(), scale: scale).plan(tree, in: rect)
  let contents = try #require(await plan.painted(scale: scale))
  let host = CALayer()
  host.bounds = rect
  contents.show(in: host)
  let layered = try bitmap(scale: scale)
  host.render(in: layered)
  return (pixels(of: single), pixels(of: layered))
}

/// How many pixels differ by more than a tolerance in a component, and the largest difference.
private func differences(_ a: [UInt8], _ b: [UInt8], tolerance: Int = 2) -> (count: Int, largest: Int) {
  var count = 0
  var largest = 0
  for pixel in stride(from: 0, to: min(a.count, b.count), by: 4) {
    let difference = (0..<4).map { abs(Int(a[pixel + $0]) - Int(b[pixel + $0])) }.max() ?? 0
    largest = max(largest, difference)
    if difference > tolerance { count += 1 }
  }
  return (count, largest)
}

/// Keyframes that rotate (`s`), fade (`f`) and move (`m`) an element.
private let keyframes =
  "<style>@keyframes s { to { transform: rotate(90deg) } } @keyframes f { to { opacity: 0.2 } }"
  + " @keyframes m { to { transform: translate(30px, 10px) } }</style>"

@MainActor
@Suite("Layer trees")
struct LayerTreeTests {
  /// Documents, and whether they rotate an element.
  nonisolated private static let documents: [(String, Bool)] = [
    (
      #"<rect x="10" y="10" width="50" height="30" fill="red"/>"#
        + #"<circle cx="60" cy="60" r="20" fill="blue" stroke="black" stroke-width="4"/>"#, false
    ),
    (
      #"<g opacity="0.5"><rect width="60" height="60" fill="red"/>"#
        + #"<rect x="30" y="30" width="60" height="60" fill="blue"/></g>"#, false
    ),
    // The layer of a moving element is between the layers painted before and after it.
    (
      keyframes + #"<rect width="40" height="40" fill="red"/>"#
        + #"<rect x="20" y="20" width="40" height="40" fill="green" style="animation: m 1s linear"/>"#
        + #"<rect x="40" y="40" width="40" height="40" fill="blue"/>"#, false
    ),
    (
      keyframes + #"<rect x="20" y="20" width="40" height="40" fill="green" style="animation: f 1s linear"/>"#, false
    ),
    (
      keyframes
        + #"<rect x="20" y="20" width="40" height="40" fill="green" "#
        + #"style="animation: s 1s linear; transform-origin: center; transform-box: fill-box"/>"#, true
    ),
    (
      keyframes + #"<svg x="10" y="10" width="50" height="50" viewBox="0 0 10 10">"#
        + #"<rect width="20" height="20" fill="green" style="animation: m 1s linear"/></svg>"#, false
    ),
    (
      keyframes
        + #"<defs><rect id="d" width="20" height="20" fill="green" stroke="black" style="animation: s 1s linear"/></defs>"#
        + ##"<use href="#d" x="40" y="40" opacity="0.5"/>"##, true
    ),
    // Elements with a clip path, a mask and a filter are painted with them in their layers.
    (
      keyframes + #"<clipPath id="c"><circle cx="20" cy="20" r="20"/></clipPath>"#
        + #"<mask id="k"><rect width="100" height="100" fill="white"/><rect width="20" height="100" fill="black"/></mask>"#
        + #"<filter id="b"><feGaussianBlur stdDeviation="2"/></filter>"#
        + ##"<rect x="10" y="10" width="40" height="40" fill="green" clip-path="url(#c)" style="animation: m 1s linear"/>"##
        + ##"<rect x="50" y="10" width="40" height="40" fill="blue" mask="url(#k)" style="animation: f 1s linear"/>"##
        + ##"<rect x="20" y="60" width="30" height="30" fill="red" filter="url(#b)" style="animation: m 1s linear"/>"##,
      false
    ),
  ]

  @Test("layers show what a rendering into one bitmap shows", arguments: documents, [0, 0.5])
  func agreement(document: (content: String, rotates: Bool), time: Double) async throws {
    for scale in [1.0, 2.0] {
      let (single, layers) = try await renderings(document.content, at: time, scale: scale)
      let (count, largest) = differences(single, layers)
      if document.rotates {
        // The screen resamples a rotated layer, which changes the antialiased edges.
        #expect(count <= single.count / 4 / 30, "\(count) pixels differ by up to \(largest) at the scale \(scale)")
      } else {
        #expect(count == 0, "\(count) pixels differ by up to \(largest) at the scale \(scale)")
      }
    }
  }
}
