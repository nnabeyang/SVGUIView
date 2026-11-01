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

/// A document with the content at the times, rendered into one bitmap and into layers, one time after another, where
/// the layers of a time reuse the ones of the time before.
///
/// - Parameter root: The attributes of the root `<svg>` element.
@MainActor
private func renderings(
  _ content: String, root: String = #"viewBox="0 0 100 100""#, at times: [Double], scale: CGFloat
) async throws -> [(bitmap: [UInt8], layers: [UInt8])] {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" "# + root + ">" + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let rect = CGRect(origin: .zero, size: size)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let planner = LayerPlanner(
    promoted: base.elementsWithAnimatedCompositing(), painting: base.elementsWithAnimatedPainting(), scale: scale)
  let host = CALayer()
  host.bounds = rect
  let layerTree = LayerTree(host: host)
  var previous: RenderedContainer?
  var renderings = [(bitmap: [UInt8], layers: [UInt8])]()
  for time in times {
    let tree = try #require(
      await RenderTreeBuilder(base: base.at(time: time), viewPort: rect, scale: scale).build(fit: fit))
    let single = try bitmap(scale: scale)
    await CGPainter(scale: scale).paint(tree, into: single)
    let contents = try #require(await planner.plan(tree, in: rect).painted(scale: scale, reusing: previous))
    layerTree.show(contents)
    previous = contents
    let layered = try bitmap(scale: scale)
    host.render(in: layered)
    renderings.append((pixels(of: single), pixels(of: layered)))
  }
  return renderings
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
  /// Documents, and whether they move an element.
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
        + #"<rect x="40" y="40" width="40" height="40" fill="blue"/>"#, true
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
        + #"<rect width="20" height="20" fill="green" style="animation: m 1s linear"/></svg>"#, true
    ),
    (
      keyframes
        + #"<defs><rect id="d" width="20" height="20" fill="green" stroke="black" style="animation: s 1s linear"/></defs>"#
        + ##"<use href="#d" x="40" y="40" opacity="0.5"/>"##, true
    ),
    // Layers whose elements change their fill are painted again, and the others are reused.
    (
      keyframes + "<style>@keyframes c { from { fill: red } to { fill: lime } }</style>"
        + #"<rect width="40" height="40" fill="blue"/>"#
        + #"<rect x="20" y="20" width="40" height="40" style="animation: c 1s linear"/>"#
        + #"<rect x="40" y="40" width="40" height="40" fill="green" style="animation: m 1s linear"/>"#
        + #"<g style="animation: c 1s linear"><rect x="60" y="0" width="20" height="20"/>"#
        + #"<rect x="70" y="70" width="20" height="20" style="animation: m 1s linear"/></g>"#, true
    ),
    // A layer under a transform that scales the axes differently has the pixels of the screen along both axes.
    (
      keyframes + #"<g transform="scale(2.4, 1.8)"><rect x="2" y="2" width="10" height="10" fill="red"/>"#
        + #"<text x="2" y="25" font-size="8">Ab</text>"#
        + #"<rect x="20" y="2" width="10" height="10" fill="blue" style="animation: f 1s linear"/></g>"#, false
    ),
    // Text with tspans that move and change their opacity, whose glyphs are painted with their own fills.
    (
      keyframes
        + #"<text x="10" y="30" font-size="12" fill="blue" style="animation: m 1s linear">A<tspan fill="red">b</tspan>"#
        + #"<tspan dy="8" fill="green">c</tspan></text><text x="10" y="70" font-size="12" style="animation: f 1s linear">"#
        + #"d<tspan x="40" fill="orange">e</tspan></text>"#, true
    ),
    // Text with lines of text-decoration under and through the glyphs of tspans, some of which move.
    (
      keyframes
        + #"<text x="10" y="30" font-size="12" text-decoration="underline" style="animation: m 1s linear">A"#
        + #"<tspan fill="red" text-decoration="line-through">bc</tspan>d</text>"#, true
    ),
    // Elements with a clip path, a mask and a filter are painted with them in their layers.
    (
      keyframes + #"<clipPath id="c"><circle cx="20" cy="20" r="20"/></clipPath>"#
        + #"<mask id="k"><rect width="100" height="100" fill="white"/><rect width="20" height="100" fill="black"/></mask>"#
        + #"<filter id="b"><feGaussianBlur stdDeviation="2"/></filter>"#
        + ##"<rect x="10" y="10" width="40" height="40" fill="green" clip-path="url(#c)" style="animation: m 1s linear"/>"##
        + ##"<rect x="50" y="10" width="40" height="40" fill="blue" mask="url(#k)" style="animation: f 1s linear"/>"##
        + ##"<rect x="20" y="60" width="30" height="30" fill="red" filter="url(#b)" style="animation: m 1s linear"/>"##,
      true
    ),
  ]

  /// Documents whose edges fall between the pixels of the screen, with the attributes of their root elements.
  nonisolated private static let edges: [(String, String)] = [
    // A diagonal line that the edge of the view cuts.
    (#"<line x2="160" y2="180" stroke="green"/>"#, #"viewBox="0 0 200 200""#),
    // The cells of a pattern end between pixels, and the layer starts away from the origin of the view.
    (
      #"<pattern id="p" patternUnits="userSpaceOnUse" width="100" height="100" viewBox="0 0 10 10">"#
        + #"<circle cx="5" cy="5" r="1.9" fill="red"/></pattern>"#
        + ##"<rect x="1" y="1" width="200" height="200" fill="url(#p)"/>"##, #"viewBox="0 0 480 360""#
    ),
    // The viewport of the root element clips its content where the margins of the fit end, between pixels.
    (#"<rect x="-100" y="-100" width="680" height="560" fill="blue"/>"#, #"width="100%" height="100%" viewBox="0 0 480 360""#),
    // Content whose edges lie on the clip of the viewport, before and after an element that moves, which puts the
    // content in layers of their own. The clip applies once to the content of the layers composited together.
    (
      keyframes + #"<rect width="480" height="360" fill="white"/>"#
        + #"<rect x="200" y="100" width="40" height="40" fill="green" style="animation: f 1s linear"/>"#
        + #"<rect width="480" height="360" fill="none" stroke="black" stroke-width="2"/>"#,
      #"width="100%" height="100%" viewBox="0 0 480 360""#
    ),
    // The same, with an element that moves, which puts the content of the viewport in layers of their own.
    (
      keyframes + #"<rect x="-100" y="-100" width="680" height="560" fill="blue"/>"#
        + #"<rect x="200" y="100" width="40" height="40" fill="green" style="animation: f 1s linear"/>"#,
      #"width="100%" height="100%" viewBox="0 0 480 360""#
    ),
  ]

  /// The attributes of root elements with transforms, and whether they move.
  nonisolated private static let rootTransforms: [(String, Bool)] = [
    (#"viewBox="0 0 100 100" transform="rotate(30)""#, false),
    (#"viewBox="0 0 100 100" transform="translate(10.25, 20)""#, false),
    (#"width="100%" height="100%" viewBox="0 0 480 360" style="animation: s 1s linear""#, true),
  ]

  @Test("layers show the transform of the root element as a rendering into one bitmap does", arguments: rootTransforms)
  func rootTransformAgreement(document: (root: String, moves: Bool)) async throws {
    let content =
      keyframes + #"<rect x="-50" y="-50" width="600" height="600" fill="white"/>"#
      + #"<rect x="10" y="10" width="50" height="30" fill="red"/>"#
      + #"<circle cx="60" cy="60" r="20" fill="blue" stroke="black" stroke-width="4"/>"#
    let times = [0, 0.25, 0.5]
    for scale in [1.0, 2.0] {
      let renderings = try await renderings(content, root: document.root, at: times, scale: scale)
      for (time, (single, layers)) in zip(times, renderings) {
        let (count, largest) = differences(single, layers)
        let description = "\(count) pixels differ by up to \(largest) at the time \(time) and the scale \(scale)"
        if document.moves {
          // The screen resamples the edges of the shapes and of the viewport that turns with them.
          #expect(count <= single.count / 4 / 15, "\(description)")
        } else {
          #expect(count == 0, "\(description)")
        }
      }
      // The root element turns in the bitmap.
      if document.moves {
        #expect(renderings[0].bitmap != renderings[2].bitmap)
      }
    }
  }

  @Test("layers show the edges between pixels as a rendering into one bitmap does", arguments: edges)
  func edgeAgreement(document: (content: String, root: String)) async throws {
    for scale in [1.0, 2.0, 3.0] {
      let (single, layers) = try #require(
        try await renderings(document.content, root: document.root, at: [0], scale: scale).first)
      let (count, largest) = differences(single, layers)
      #expect(count == 0, "\(count) pixels differ by up to \(largest) at the scale \(scale)")
    }
  }

  /// The layers of a document at the times, shown one time after another in the same host, after each time.
  private func shownLayers(_ content: String, root: String, at times: [Double], scale: CGFloat) async throws -> [[CALayer]] {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" "# + root + ">" + content + "</svg>"
    let base = SVGParser.parse(data: Data(svg.utf8))
    let rect = CGRect(origin: .zero, size: size)
    let fit = ContentFit(
      preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
    let planner = LayerPlanner(
      promoted: base.elementsWithAnimatedCompositing(), painting: base.elementsWithAnimatedPainting(), scale: scale)
    let host = CALayer()
    let layerTree = LayerTree(host: host)
    var previous: RenderedContainer?
    var shown = [[CALayer]]()
    func all(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(all) }
    for time in times {
      let tree = try #require(
        await RenderTreeBuilder(base: base.at(time: time), viewPort: rect, scale: scale).build(fit: fit))
      let contents = try #require(await planner.plan(tree, in: rect).painted(scale: scale, reusing: previous))
      layerTree.show(contents)
      previous = contents
      shown.append(all(host))
    }
    return shown
  }

  @Test("the clip of a viewport between the pixels clips its layers once by a mask, and one on the pixels masks to bounds")
  func viewportClips() async throws {
    let content =
      keyframes + #"<rect width="100%" height="100%" fill="white"/>"#
      + #"<rect x="20" y="20" width="40" height="40" fill="green" style="animation: f 1s linear"/>"#
    // A view box of 480 by 360 leaves margins of 12.5 points above and below.
    let between = try await shownLayers(
      content, root: #"width="100%" height="100%" viewBox="0 0 480 360""#, at: [0, 0.5], scale: 1)
    let masked = between.map { $0.filter { $0.mask != nil } }
    #expect(masked.map(\.count) == [1, 1])
    #expect(masked[0].first?.masksToBounds == false)
    // The mask of the next time is the same layer with the same image.
    #expect(masked[0].first?.mask === masked[1].first?.mask)
    #expect((masked[0].first?.mask?.contents as AnyObject?) === (masked[1].first?.mask?.contents as AnyObject?))
    let onPixels = try await shownLayers(
      content, root: #"width="100%" height="100%" viewBox="0 0 100 100""#, at: [0], scale: 1)
    #expect(onPixels[0].allSatisfy { $0.mask == nil })
    // The layer that clips to the view, and the one that clips to the viewport.
    #expect(onPixels[0].count { $0.masksToBounds } == 2)
  }

  @Test("layers show what a rendering into one bitmap shows, at one time after another", arguments: documents)
  func agreement(document: (content: String, moves: Bool)) async throws {
    let times = [0, 0.25, 0.5, 0.75]
    for scale in [1.0, 2.0] {
      for (time, (single, layers)) in zip(times, try await renderings(document.content, at: times, scale: scale)) {
        let (count, largest) = differences(single, layers)
        let description = "\(count) pixels differ by up to \(largest) at the time \(time) and the scale \(scale)"
        if document.moves {
          // A moving layer keeps its pixels, which the screen resamples where it rotates them or moves them between
          // the pixels of the screen, which changes the antialiased edges.
          #expect(count <= single.count / 4 / 30, "\(description)")
        } else {
          #expect(count == 0, "\(description)")
        }
      }
    }
  }
}
