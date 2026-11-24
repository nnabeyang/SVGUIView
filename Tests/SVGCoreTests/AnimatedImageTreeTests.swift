import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// Tests that render trees show the SVG images at the time of the timeline of their documents, parse each image once
/// for the renderings that share the parsed images, and tell which elements show images that animate.
@Suite("Animated images in render trees")
struct AnimatedImageTreeTests {
  /// The data URL of an SVG image whose square is at x 0 and moves to x 10 by `<set>` at 1 s, until 2 s and after.
  private static let movingImage = url(
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="10" height="10"><set attributeName="x" to="10" begin="1s" dur="1s" fill="freeze"/></rect></svg>"#
  )
  private static let stillImage = url(
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="10" height="10"/></svg>"#)

  private static func url(_ svg: String) -> String {
    "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
  }

  private func tree(
    _ content: String, at time: Double, documents: SVGImageDocuments = SVGImageDocuments()
  ) async throws -> RenderTree {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let base = SVGParser.parse(data: Data(svg.utf8), languages: ["en-US"])
    let builder = RenderTreeBuilder(
      base: base, viewPort: CGRect(x: 0, y: 0, width: 20, height: 20), scale: 1, time: time,
      imageDocuments: documents)
    return try #require(await builder.build(fit: ContentFit(preserveAspectRatio: .none)))
  }

  /// The bounds of what the SVG image of the first child of a tree paints, in the coordinates of the image.
  private func painted(_ tree: RenderTree) throws -> CGRect {
    let child = try #require(tree.root?.viewport?.content?.children.first)
    let image = try #require(child.shape?.content?.image?.paint?.content.document, "The image isn't a document")
    return image.paintedBounds(filtersWithin: nil)
  }

  @Test("an SVG image shows its animations at the time of the document")
  func time() async throws {
    let content = #"<image width="20" height="20" href="\#(Self.movingImage)"/>"#
    let before = try painted(try await tree(content, at: 0.5))
    let after = try painted(try await tree(content, at: 1.5))
    #expect(before.minX == 0 && before.width == 10)
    #expect(after.minX == 10 && after.width == 10)
  }

  @Test("the renderings that share the parsed images parse each image once")
  func parsedOnce() async throws {
    let documents = SVGImageDocuments()
    let data = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>"#.utf8)
    let first = documents.document(of: data, languages: ["en-US"])
    let second = documents.document(of: data, languages: ["en-US"])
    #expect(first.context.root === second.context.root)
    #expect(documents.document(of: data, languages: ["ja-JP"]).context.root !== first.context.root)
  }

  @Test("a tree tells the elements that show animated images, and when the images stop changing")
  func hosts() async throws {
    let animated = try await tree(
      #"<g><image id="a" width="10" height="10" href="\#(Self.movingImage)"/></g>"#
        + #"<image width="10" height="10" href="\#(Self.stillImage)"/>"#, at: 0)
    let image = try #require(animated.animatedImages.hosts.first)
    #expect(animated.animatedImages.hosts.count == 1)
    #expect(animated.animatedImages.end == 2)
    #expect(!animated.animatedImages.requiresFullRepaint)
    // The group and the root have the node of the image.
    #expect(animated.animatedImages.ancestors.count == 2)
    #expect(
      image
        == animated.root.flatMap { root -> ElementID? in
          var found = Set<ElementID>()
          var ancestors = Set<ElementID>()
          root.elements(in: [image], into: &found, ancestors: &ancestors)
          return found.first
        })
    let still = try await tree(#"<image width="10" height="10" href="\#(Self.stillImage)"/>"#, at: 0)
    #expect(still.animatedImages.isEmpty)
  }

  @Test("an animated image that a pattern or a feImage draws makes its users change")
  func paintsAndFilters() async throws {
    let pattern = try await tree(
      #"<pattern id="p" width="1" height="1"><image width="20" height="20" href="\#(Self.movingImage)"/></pattern>"#
        + #"<rect width="20" height="20" fill="url(#p)"/>"#, at: 0)
    #expect(pattern.animatedImages.hosts.count == 1)
    #expect(pattern.animatedImages.requiresFullRepaint)
    let filter = try await tree(
      #"<filter id="f"><feImage href="\#(Self.movingImage)"/></filter><rect id="r" width="20" height="20" filter="url(#f)"/>"#,
      at: 0)
    #expect(filter.animatedImages.hosts.count == 1)
    #expect(!filter.animatedImages.requiresFullRepaint)
  }
}
