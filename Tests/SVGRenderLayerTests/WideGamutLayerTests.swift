import CoreGraphics
import Foundation
import Testing

@testable import SVGCore
@testable import SVGRenderLayer

/// The images of the painted layers of a document whose rectangle moves, in a wide gamut or not.
private func images(fill: String, wideGamut: Bool) async throws -> [CGImage] {
  let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <style>@keyframes m { to { transform: translate(30px, 10px) } }</style>
      <rect width="20" height="20" fill="\#(fill)" style="animation: m 1s linear"/>
    </svg>
    """#
  let base = SVGParser.parse(data: Data(document.utf8))
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base.at(time: 0.5), viewPort: rect, scale: 1).build(fit: fit))
  let planner = LayerPlanner(
    promoted: base.elementsWithAnimatedCompositing(), painting: base.elementsWithAnimatedPainting(), scale: 1)
  let layers = try #require(await planner.plan(tree, in: rect).painted(scale: 1, wideGamut: wideGamut))
  return layers.paintedContents.compactMap(\.image)
}

@Suite("Layers in a wide gamut")
struct WideGamutLayerTests {
  @Test("the layers of a wide gamut are painted in Display P3")
  func displayP3() async throws {
    let images = try await images(fill: "color(display-p3 1 0 0)", wideGamut: true)
    #expect(!images.isEmpty)
    #expect(images.allSatisfy { $0.colorSpace?.name == CGColorSpace.displayP3 })
  }

  @Test("the layers that aren't of a wide gamut are painted in device RGB")
  func deviceRGB() async throws {
    let images = try await images(fill: "color(display-p3 1 0 0)", wideGamut: false)
    #expect(!images.isEmpty)
    #expect(images.allSatisfy { $0.colorSpace?.name != CGColorSpace.displayP3 })
  }
}
