import CoreGraphics
import Foundation
import Testing

@testable import SVGUIView

@Suite("ResolveContext")
struct ResolveContextTests {
  private func makeContext(viewPort: CGRect, scale: CGFloat = 1) -> ResolveContext {
    let base = SVGParser.parse(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8))
    return ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: viewPort)
  }

  @Test("the text scale comes from the scale that rendering starts with")
  func textScaleUsesScale() {
    let context = makeContext(viewPort: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 3)
    #expect(abs(context.textScale - 3) < 1e-9)
  }

  @Test("making a font cascade doesn't change the ones made before from the same font")
  func fontCascadesDontShareDescription() {
    let context = makeContext(viewPort: CGRect(x: 0, y: 0, width: 100, height: 100))
    // A document holds its fonts, and renderings at different sizes make cascades from the same one at once.
    let font = SVGUIFont(name: "Helvetica", size: .length(.pixel(10)), weight: .normal)
    let small = font.fontCascade(textScale: 1, context: context)
    let large = font.fontCascade(textScale: 3, context: context)
    #expect(small.fontDescription !== large.fontDescription)
    #expect(small.fontDescription.computedSize == 10)
    #expect(large.fontDescription.computedSize == 30)
  }
}
