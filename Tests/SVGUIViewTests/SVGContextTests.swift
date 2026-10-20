import CoreGraphics
import Foundation
import Testing

@testable import SVGUIView

@Suite("SVGContext")
struct SVGContextTests {
  private func makeContext(viewPort: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) throws -> SVGContext {
    let base = SVGParser.parse(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8))
    let graphics = try #require(
      CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return SVGContext(base: base, graphics: graphics, viewPort: viewPort, scale: scale)
  }

  @Test("the text scale comes from the scale that rendering starts with")
  func textScaleUsesScale() throws {
    let viewPort = CGRect(x: 0, y: 0, width: 100, height: 50)
    let context = try makeContext(viewPort: viewPort, scale: 3)
    context.push(viewBox: viewPort)
    #expect(abs(context.textScale - 3) < 1e-9)
  }

  @Test("popping the tag ID stack leaves the clip ID stack alone")
  func popTagIdStackKeepsClipIdStack() throws {
    let context = try makeContext()
    context.pushClipIdStack()
    context.pushTagIdStack()
    context.popTagIdStack()
    // `check` returns false when there is no level to record the ID in.
    #expect(context.check(clipId: "clip"))
  }

  @Test("popping the tag ID stack returns to the outer level")
  func popTagIdStackReturnsToOuterLevel() throws {
    let context = try makeContext()
    let tagId = ObjectIdentifier(NSObject.self)
    context.pushTagIdStack()
    #expect(context.check(tagId: tagId))
    context.pushTagIdStack()
    context.popTagIdStack()
    // The outer level already holds the ID, so it is reported as a recursive reference.
    #expect(!context.check(tagId: tagId))
  }

  @Test("making a font cascade doesn't change the ones made before from the same font")
  func fontCascadesDontShareDescription() throws {
    let context = try makeContext(viewPort: CGRect(x: 0, y: 0, width: 100, height: 100))
    context.push(viewBox: CGRect(x: 0, y: 0, width: 100, height: 100))
    // A document holds its fonts, and renderings at different sizes make cascades from the same one at once.
    let font = SVGUIFont(name: "Helvetica", size: "10", weight: nil)
    let small = font.fontCascade(textScale: 1, context: context)
    let large = font.fontCascade(textScale: 3, context: context)
    #expect(small.fontDescription !== large.fontDescription)
    #expect(small.fontDescription.computedSize == 10)
    #expect(large.fontDescription.computedSize == 30)
  }
}
