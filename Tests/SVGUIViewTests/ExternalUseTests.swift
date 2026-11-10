import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// A folder of SVG files in the temporary folder, which is removed when it's released.
private final class SVGFolder {
  let url: URL

  init(_ files: [String: String]) throws {
    url = FileManager.default.temporaryDirectory.appending(path: "ExternalUse-\(UUID().uuidString)")
    for (path, text) in files {
      let file = url.appending(path: path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: file)
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

/// An SVG document in the user space of 20 by 20.
private func svg(_ content: String) -> String {
  #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
}

@MainActor
@Suite("Use elements that show elements of other documents")
struct ExternalUseTests {
  /// The snapshot of a document of a folder in a view of 20 by 20, at a scale of 1.
  private func render(_ path: String, in folder: SVGFolder) async throws -> Rendering {
    let url = folder.url.appending(path: path)
    let view = try #require(SVGUIView(contentsOf: url))
    view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    let image = try #require(try await view.takeSnapshot(scale: 1).cgImage)
    return Rendering(components: try pixels(of: image), width: image.width, scale: 1)
  }

  private static let lime: [UInt8] = [0, 255, 0, 255]
  private static let red: [UInt8] = [255, 0, 0, 255]
  private static let clear: [UInt8] = [0, 0, 0, 0]

  @Test("a use element shows an element of another document, which inherits from the use element")
  func element() async throws {
    let folder = try SVGFolder([
      "doc.svg": svg(##"<use href="shapes.svg#r" fill="lime"/>"##),
      "shapes.svg": svg(#"<rect id="r" width="20" height="20"/>"#),
    ])
    #expect(try await render("doc.svg", in: folder).pixel(x: 10, y: 10) == Self.lime)
  }

  @Test("a use element fits the svg element of another document into its width and height")
  func svgElement() async throws {
    let folder = try SVGFolder([
      "doc.svg": svg(##"<use href="shapes.svg#root" width="10" height="10"/>"##),
      "shapes.svg":
        #"<svg xmlns="http://www.w3.org/2000/svg" id="root" viewBox="0 0 1 1" width="100" height="100">"#
        + #"<rect width="1" height="1" fill="lime"/></svg>"#,
    ])
    let rendering = try await render("doc.svg", in: folder)
    #expect(rendering.pixel(x: 5, y: 5) == Self.lime)
    #expect(rendering.pixel(x: 15, y: 15) == Self.clear)
  }

  @Test(
    "a paint that the copy inherits from the use element is of the document of the use element, and its own is of its document"
  )
  func references() async throws {
    let gradient = #"<defs><linearGradient id="g"><stop stop-color="%@"/></linearGradient></defs>"#
    let folder = try SVGFolder([
      "doc.svg": svg(
        gradient.replacingOccurrences(of: "%@", with: "lime")
          + ##"<use href="shapes.svg#a" fill="url(#g)"/><use href="shapes.svg#b" fill="url(#g)"/>"##),
      "shapes.svg": svg(
        gradient.replacingOccurrences(of: "%@", with: "red")
          + #"<rect id="a" width="10" height="20"/><rect id="b" x="10" width="10" height="20" fill="url(#g)"/>"#),
    ])
    let rendering = try await render("doc.svg", in: folder)
    #expect(rendering.pixel(x: 5, y: 10) == Self.lime)
    #expect(rendering.pixel(x: 15, y: 10) == Self.red)
  }

  @Test("a document that shows itself again through other documents stops there", .timeLimit(.minutes(1)))
  func cycle() async throws {
    let folder = try SVGFolder([
      "a.svg": svg(##"<use id="u" href="b.svg#v"/><rect id="r" width="10" height="20" fill="lime"/>"##),
      "b.svg": svg(##"<g id="v"><use href="a.svg#u"/><rect x="10" width="10" height="20" fill="lime"/></g>"##),
    ])
    let rendering = try await render("a.svg", in: folder)
    #expect(rendering.pixel(x: 5, y: 10) == Self.lime)
    #expect(rendering.pixel(x: 15, y: 10) == Self.lime)
  }

  @Test("a use element doesn't show elements of documents outside the folder, of data URLs, or that aren't there")
  func unread() async throws {
    let data =
      "data:image/svg+xml," + #"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="20" height="20"/></svg>"#
      .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    let folder = try SVGFolder([
      "docs/doc.svg": svg(
        ##"<use href="../shapes.svg#r" fill="red"/><use href="\##(data)#r" fill="red"/>"##
          + ##"<use href="missing.svg#r" fill="red"/><use href="shapes.svg#missing" fill="red"/>"##),
      "docs/shapes.svg": svg(#"<rect id="other" width="20" height="20"/>"#),
      "shapes.svg": svg(#"<rect id="r" width="20" height="20"/>"#),
    ])
    #expect(try await render("docs/doc.svg", in: folder).pixel(x: 10, y: 10) == Self.clear)
  }
}
