import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// A folder of files in the temporary folder, which is removed when it's released.
private final class StyleFolder {
  let url: URL

  init(_ files: [String: String]) throws {
    url = FileManager.default.temporaryDirectory.appending(path: "ExternalStyleSheets-\(UUID().uuidString)")
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

/// Reads nothing until the task is cancelled, and tells when it starts.
private final class HeldReading: Sendable {
  private let continuation: AsyncStream<Void>.Continuation
  let started: AsyncStream<Void>

  init() {
    (started, continuation) = AsyncStream.makeStream()
  }

  var fetch: @Sendable (URL) async throws -> Data {
    { _ in
      self.continuation.yield()
      try await Task.sleep(for: .seconds(600))
      return Data()
    }
  }
}

@MainActor
@Suite("Style sheets in other files of a view")
struct ExternalStyleSheetViewTests {
  /// A document of a square of 20 whose fill a style sheet in another file sets to lime.
  private static let document =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"#
    + #"<style>@import url(styles/lime.css);</style><rect id="r" width="20" height="20"/></svg>"#
  private static let files = ["doc.svg": document, "styles/lime.css": "#r { fill: lime }"]

  private static let lime: [UInt8] = [0, 255, 0, 255]
  private static let black: [UInt8] = [0, 0, 0, 255]

  /// The pixel at the center of the snapshot of a view of 20 by 20, at a scale of 1.
  private func center(of view: SVGUIView, timeout: Duration = patience) async throws -> [UInt8] {
    view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    view.configuration = SVGUIViewConfiguration(
      timeoutDuration: timeout, externalResources: view.configuration.externalResources)
    let image = try #require(try await view.takeSnapshot(scale: 1).cgImage)
    return Rendering(components: try pixels(of: image), width: image.width, scale: 1).pixel(x: 10, y: 10)
  }

  @Test("a document opened from a URL, or given with a base URL, takes the style sheets in other files")
  func styleSheets() async throws {
    let folder = try StyleFolder(Self.files)
    let url = folder.url.appending(path: "doc.svg")
    #expect(try await center(of: try #require(SVGUIView(contentsOf: url))) == Self.lime)
    let view = SVGUIView()
    await view.setData(Data(Self.document.utf8), baseURL: url)
    #expect(try await center(of: view) == Self.lime)
    // Data without a base URL reads no files.
    #expect(try await center(of: SVGUIView(data: Data(Self.document.utf8))) == Self.black)
  }

  @Test("the configuration decides whether the style sheets in other files are read, also after they were read")
  func configuration() async throws {
    let folder = try StyleFolder(Self.files)
    let view = try #require(SVGUIView(contentsOf: folder.url.appending(path: "doc.svg")))
    #expect(try await center(of: view) == Self.lime)
    view.configuration = SVGUIViewConfiguration(externalResources: .none)
    #expect(try await center(of: view) == Self.black)
    view.configuration = SVGUIViewConfiguration()
    #expect(try await center(of: view) == Self.lime)
  }

  @Test("the changes of the document API stay with the document that takes the style sheets")
  func documentChanges() async throws {
    let folder = try StyleFolder(Self.files)
    let view = try #require(SVGUIView(contentsOf: folder.url.appending(path: "doc.svg")))
    view.document.element(id: "r")?.setAttribute("width", to: "5")
    #expect(try await center(of: view) == [0, 0, 0, 0])
    view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    let image = try #require(try await view.takeSnapshot(scale: 1).cgImage)
    #expect(Rendering(components: try pixels(of: image), width: image.width, scale: 1).pixel(x: 2, y: 10) == Self.lime)
  }

  @Test("a use element shows an element of another document with the style sheets of that document")
  func externalUse() async throws {
    let folder = try StyleFolder([
      "doc.svg": #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><use href="shapes/s.svg#r"/></svg>"#,
      "shapes/s.svg": #"<?xml-stylesheet href="s.css" type="text/css"?>"#
        + #"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="20" height="20"/></svg>"#,
      "shapes/s.css": "#r { fill: lime }",
    ])
    #expect(try await center(of: try #require(SVGUIView(contentsOf: folder.url.appending(path: "doc.svg")))) == Self.lime)
  }

  @Test("reading the style sheets takes part of the time of a rendering, which times out", .timeLimit(.minutes(1)))
  func timeout() async throws {
    let folder = try StyleFolder(Self.files)
    let view = try #require(SVGUIView(contentsOf: folder.url.appending(path: "doc.svg")))
    let reading = HeldReading()
    await #expect(throws: SVGRenderingError.timedOut) {
      try await SVGUIView.$resourceFetch.withValue(reading.fetch) {
        _ = try await center(of: view, timeout: .milliseconds(200))
      }
    }
  }

  @Test("cancelling the task that waits for a snapshot stops reading the style sheets", .timeLimit(.minutes(1)))
  func cancellation() async throws {
    let folder = try StyleFolder(Self.files)
    let view = try #require(SVGUIView(contentsOf: folder.url.appending(path: "doc.svg")))
    view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(600))
    let reading = HeldReading()
    let task = SVGUIView.$resourceFetch.withValue(reading.fetch) {
      Task { _ = try await view.takeSnapshot() }
    }
    for await _ in reading.started { break }
    task.cancel()
    let result = await task.result
    #expect(throws: SVGRenderingError.cancelled) { try result.get() }
  }
}
