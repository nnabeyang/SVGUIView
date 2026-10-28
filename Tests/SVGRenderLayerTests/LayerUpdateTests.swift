import CoreGraphics
import Foundation
import QuartzCore
import Testing

@testable import SVGCore
@testable import SVGRenderLayer

/// A document whose second rectangle `r` moves and third rectangle `f` changes its fill.
private let document = #"""
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
    <style>
      @keyframes m { to { transform: translate(30px, 10px) } }
      @keyframes c { from { fill: red } to { fill: lime } }
    </style>
    <rect id="a" width="20" height="20"/>
    <rect id="r" x="20" width="20" height="20" style="animation: m 1s linear"/>
    <rect id="f" x="40" width="20" height="20" style="animation: c 1s linear"/>
  </svg>
  """#

/// A document whose second rectangle `r` moves with a filter that doesn't change, and whose third rectangle `f` has a
/// filter whose blur changes.
private let filters = #"""
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
    <style>@keyframes m { to { transform: translate(30px, 10px) } }</style>
    <filter id="still"><feGaussianBlur stdDeviation="2"/></filter>
    <filter id="pulse">
      <feGaussianBlur stdDeviation="1"><animate attributeName="stdDeviation" to="4" dur="1s"/></feGaussianBlur>
    </filter>
    <rect id="a" width="20" height="20"/>
    <rect id="r" x="20" y="40" width="20" height="20" filter="url(#still)" style="animation: m 1s linear"/>
    <rect id="f" x="60" y="40" width="20" height="20" filter="url(#pulse)"/>
  </svg>
  """#

/// The layers of a document at the time, which reuse the previous ones.
private func layers(
  of document: String = document, at time: Double, reusing previous: RenderedContainer? = nil
) async throws -> RenderedContainer {
  let base = SVGParser.parse(data: Data(document.utf8))
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base.at(time: time), viewPort: rect, scale: 1).build(fit: fit))
  let planner = LayerPlanner(
    promoted: base.elementsWithAnimatedCompositing(), painting: base.elementsWithAnimatedPainting(), scale: 1)
  return try #require(await planner.plan(tree, in: rect).painted(scale: 1, reusing: previous))
}

/// The contents of the painted layers in a container, in order.
private func contents(of container: RenderedContainer) -> [PaintedContents] {
  container.children.flatMap { child -> [PaintedContents] in
    switch child {
    case .container(let container): contents(of: container)
    case .painted(let contents): [contents]
    }
  }
}

/// The layers in a layer, at every depth, in order.
private func sublayers(of layer: CALayer) -> [CALayer] {
  (layer.sublayers ?? []).flatMap { [$0] + sublayers(of: $0) }
}

@Suite("Updating layers")
struct LayerUpdateTests {
  @Test("the next time shows the images of the layers that don't change, and paints the others again")
  func reusesImages() async throws {
    let first = try await layers(at: 0)
    let second = try await layers(at: 0.5, reusing: first)
    let before = contents(of: first)
    let after = contents(of: second)
    // The rectangle before the moving one, the moving one in its layer, and the one whose fill changes.
    try #require(before.count == 3 && after.count == 3)
    #expect(after[0].image === before[0].image)
    #expect(after[1].image === before[1].image)
    #expect(after[2].image !== before[2].image)
    #expect(second.paintedCount(since: first) == 1)
    #expect(second.paintedCount(since: nil) == 3)
    // Without the previous layers, everything is painted.
    #expect(contents(of: try await layers(at: 0.5)).allSatisfy { $0.image !== before[0].image })
  }

  @Test("an animation inside a filter paints again only the elements that use the filter")
  func reusesImagesWithFilters() async throws {
    let first = try await layers(of: filters, at: 0)
    let second = try await layers(of: filters, at: 0.5, reusing: first)
    let before = contents(of: first)
    let after = contents(of: second)
    // The rectangle before the moving one, the moving one in its layer, and the one whose blur changes.
    try #require(before.count == 3 && after.count == 3)
    #expect(after[0].image === before[0].image)
    #expect(after[1].image === before[1].image)
    #expect(after[2].image !== before[2].image)
    #expect(second.paintedCount(since: first) == 1)
  }

  @MainActor
  @Test("showing the next time reuses the layers, and changes only what differs")
  func reusesLayers() async throws {
    let host = CALayer()
    let tree = LayerTree(host: host)
    let first = try await layers(at: 0)
    tree.show(first)
    let shown = sublayers(of: host)
    tree.show(try await layers(at: 0.5, reusing: first))
    let next = sublayers(of: host)
    #expect(next.count == shown.count)
    #expect(zip(next, shown).allSatisfy { $0 === $1 })
    // Only the layer of the moving rectangle moves.
    #expect(next.filter { $0.affineTransform() != .identity }.count == 1)
    #expect(next.contains { $0.affineTransform() == CGAffineTransform(translationX: 15, y: 5) })
    tree.clear()
    #expect(host.sublayers == nil)
  }
}
