import Foundation
import Synchronization
import Testing

@testable import SVGCore

/// A folder of files in the temporary folder, which is removed when it's released.
private final class Folder {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appending(path: "ExternalResources-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// Writes a file at a path in the folder, with the folders it's in, and returns its URL.
  @discardableResult
  func write(_ text: String, at path: String) throws -> URL {
    let file = url.appending(path: path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
    return file
  }
}

/// Counts the files that a loader reads.
private final class FetchCounter: Sendable {
  let count = Mutex(0)

  var fetch: ExternalResourceLoader.Fetch {
    { url in
      self.count.withLock { $0 += 1 }
      return try Data(contentsOf: url)
    }
  }
}

@Suite("Reading the files that a document refers to")
struct ExternalResourceLoaderTests {
  /// The text of the file that an `href` of a document in the folder `docs` reads, when the loader reads `folder`.
  private func text(
    of href: String, in folder: Folder, allowing allowed: String = "docs", baseURL: URL? = nil
  ) async -> String? {
    let loader = ExternalResourceLoader(
      baseURL: baseURL ?? folder.url.appending(path: "docs/image.svg"), folder: folder.url.appending(path: allowed),
      cache: ExternalResourceCache())
    return await loader.data(forHref: href).map { String(decoding: $0, as: UTF8.self) }
  }

  @Test("files in the folder and in the folders inside it are read")
  func filesInFolder() async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/a.png")
    try folder.write("b", at: "docs/images/b.png")
    #expect(await text(of: "a.png", in: folder) == "a")
    #expect(await text(of: " images/b.png ", in: folder) == "b")
    #expect(await text(of: "./images/../a.png", in: folder) == "a")
    #expect(await text(of: "a.png?size=2#frame", in: folder) == "a")
    #expect(await text(of: "images/b%2Epng", in: folder) == "b")
    let absolute = folder.url.appending(path: "docs/a.png").absoluteString
    #expect(await text(of: absolute, in: folder) == "a")
  }

  @Test("files in a folder that encloses the folder of the document are read when the loader allows the folder")
  func enclosingFolder() async throws {
    let folder = try Folder()
    try folder.write("shared", at: "shared/c.png")
    #expect(await text(of: "../shared/c.png", in: folder) == nil)
    #expect(await text(of: "../shared/c.png", in: folder, allowing: "") == "shared")
  }

  @Test("files outside the folder aren't read, by a relative path, an absolute URL or a symbolic link")
  func filesOutsideFolder() async throws {
    let folder = try Folder()
    try folder.write("outside", at: "outside.png")
    let outside = try folder.write("sibling", at: "docs2/d.png")
    try folder.write("docs", at: "docs/inside.png")
    try FileManager.default.createSymbolicLink(
      at: folder.url.appending(path: "docs/link.png"), withDestinationURL: folder.url.appending(path: "outside.png"))
    try FileManager.default.createSymbolicLink(
      at: folder.url.appending(path: "docs/up"), withDestinationURL: folder.url)
    #expect(await text(of: "../outside.png", in: folder) == nil)
    #expect(await text(of: "images/../../outside.png", in: folder) == nil)
    #expect(await text(of: outside.absoluteString, in: folder) == nil)
    #expect(await text(of: "../docs2/d.png", in: folder) == nil)
    #expect(await text(of: "link.png", in: folder) == nil)
    #expect(await text(of: "up/outside.png", in: folder) == nil)
    #expect(await text(of: "up/docs/inside.png", in: folder) == "docs")
  }

  @Test(
    "references that aren't files in the folder aren't read",
    arguments: ["", "#image", "data:image/png;base64,AAAA", "https://example.com/a.png", "missing.png", "images"])
  func otherReferences(href: String) async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/images/a.png")
    #expect(await text(of: href, in: folder) == nil)
  }

  @Test("a document without a base URL, or a loader without a folder, reads nothing")
  func nothingToRead() async throws {
    let folder = try Folder()
    let file = try folder.write("a", at: "docs/a.png")
    let withoutBase = ExternalResourceLoader(
      baseURL: nil, folder: folder.url.appending(path: "docs"), cache: ExternalResourceCache())
    #expect(await withoutBase.data(forHref: file.absoluteString) == nil)
    let withoutFolder = ExternalResourceLoader(
      baseURL: folder.url.appending(path: "docs/image.svg"), folder: nil, cache: ExternalResourceCache())
    #expect(await withoutFolder.data(forHref: "a.png") == nil)
    #expect(await ExternalResourceLoader.none.data(forHref: "a.png") == nil)
  }

  @Test("a file is read once for a cache, and a file that can't be read isn't read again")
  func cache() async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/a.png")
    let counter = FetchCounter()
    let cache = ExternalResourceCache()
    let base = folder.url.appending(path: "docs/image.svg")
    let loader = ExternalResourceLoader(
      baseURL: base, folder: folder.url.appending(path: "docs"), cache: cache, fetch: counter.fetch)
    #expect(await loader.data(forHref: "a.png") != nil)
    #expect(await loader.data(forHref: "./a.png#b") != nil)
    #expect(await loader.data(forHref: "missing.png") == nil)
    #expect(await loader.data(forHref: "missing.png") == nil)
    #expect(counter.count.withLock { $0 } == 2)
    // Another loader of the same document shares the cache.
    let other = ExternalResourceLoader(
      baseURL: base, folder: folder.url.appending(path: "docs"), cache: cache, fetch: counter.fetch)
    #expect(await other.data(forHref: "a.png") != nil)
    #expect(counter.count.withLock { $0 } == 2)
  }

  @Test("a file whose reading is cancelled isn't kept, and is read again")
  func cancelledReading() async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/a.png")
    let counter = FetchCounter()
    let loader = ExternalResourceLoader(
      baseURL: folder.url.appending(path: "docs/image.svg"), folder: folder.url.appending(path: "docs"),
      cache: ExternalResourceCache(), fetch: counter.fetch)
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await loader.data(forHref: "a.png")
    }
    #expect(await cancelled.value == nil)
    #expect(await loader.data(forHref: "a.png") != nil)
    #expect(counter.count.withLock { $0 } == 2)
  }

  @Test("only a data URL is read as base64", arguments: [("data:;base64,YQ==", "a"), (" DATA:,YQ==", "a"), ("YQ==", nil)])
  func dataURL(href: String, expected: String?) {
    #expect(EmbeddedImage.data(ofHref: href).map { String(decoding: $0, as: UTF8.self) } == expected)
  }

  @Test("an image element keeps a reference to a file, and reads a data URL")
  func imageSource() throws {
    func source(_ href: String) throws -> SVGImageElement.Source? {
      let svg = #"<svg xmlns="http://www.w3.org/2000/svg"><image id="i" href="\#(href)"/></svg>"#
      let base = SVGParser.parse(data: Data(svg.utf8))
      return try #require(base["i"] as? SVGImageElement).source
    }
    #expect(try source("images/a.png") == .external("images/a.png"))
    #expect(try source("data:,YQ==") == .data(Data("a".utf8)))
    #expect(try source("#a") == nil)
    #expect(try source("") == nil)
  }
}
