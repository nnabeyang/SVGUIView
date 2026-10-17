import CoreGraphics
import Foundation
import Testing

@testable import SVGUIView

@Suite("SVGContext")
struct SVGContextTests {
  private func makeContext() throws -> SVGContext {
    let base = SVGParser.parse(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8))
    let graphics = try #require(
      CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return SVGContext(base: base, graphics: graphics, viewPort: CGRect(x: 0, y: 0, width: 1, height: 1))
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
}
