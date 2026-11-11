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

  /// Reads files, and gives the text of a URL of the network as its data.
  var networkFetch: ExternalResourceLoader.Fetch {
    { url in
      self.count.withLock { $0 += 1 }
      return url.isFileURL ? try Data(contentsOf: url) : Data(url.absoluteString.utf8)
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

  @Test(
    "a data URL is base64 where its media type says so, and percent-encoded text otherwise, without its fragment",
    arguments: [
      ("data:;base64,YQ==", "a"), (" DATA:image/png;BASE64,YQ==", "a"), ("data:;base64,YQ==#view", "a"),
      ("data:,YQ==", "YQ=="), ("data:image/svg+xml,%3Csvg%20viewBox='0,0,1,1'/%3E#v", "<svg viewBox='0,0,1,1'/>"),
      ("YQ==", nil), ("data:YQ==", nil),
    ])
  func dataURL(href: String, expected: String?) {
    #expect(EmbeddedImage.data(ofHref: href).map { String(decoding: $0, as: UTF8.self) } == expected)
  }

  @Test("the fragment of an href", arguments: [("a.svg#v", "v"), ("data:,x#v%20w", "v w"), ("a.svg", nil), ("a.svg#", nil)])
  func fragment(href: String, expected: String?) {
    #expect(EmbeddedImage.fragment(ofHref: href) == expected)
  }

  @Test("an image element keeps a reference to a file, and reads a data URL")
  func imageSource() throws {
    func source(_ href: String) throws -> SVGImageElement.Source? {
      let svg = #"<svg xmlns="http://www.w3.org/2000/svg"><image id="i" href="\#(href)"/></svg>"#
      let base = SVGParser.parse(data: Data(svg.utf8))
      return try #require(base["i"] as? SVGImageElement).source
    }
    #expect(try source("images/a.png") == .external("images/a.png"))
    #expect(try source("data:;base64,YQ==") == .data(Data("a".utf8)))
    #expect(try source("#a") == nil)
    #expect(try source("") == nil)
  }

  @Test("an xlink:href is a reference only where its prefix is bound to the XLink namespace")
  func xlinkNamespace() throws {
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
        <g xmlns:xlink="http://example.net/bar">
          <image id="other" xlink:href="a.png"/>
          <g xmlns:xlink="http://www.w3.org/1999/xlink"><image id="inner" xlink:href="b.png"/></g>
          <image id="after" xlink:href="c.png"/>
        </g>
        <image id="outer" xlink:href="d.png"/>
      </svg>
      """
    let base = SVGParser.parse(data: Data(svg.utf8))
    func source(_ id: String) throws -> SVGImageElement.Source? {
      try #require(base[id] as? SVGImageElement).source
    }
    #expect(try source("other") == nil)
    #expect(try source("inner") == .external("b.png"))
    #expect(try source("after") == nil)
    #expect(try source("outer") == .external("d.png"))
  }

  @Test(
    "a use element keeps the URL and the ID of an element of another document, and not of a data URL",
    arguments: [
      ("other.svg#a", "other.svg", "a"), (" images/b.svg#%61b ", "images/b.svg", "ab"), ("#a", nil, nil),
      ("other.svg", nil, nil), ("other.svg#", nil, nil), ("data:image/svg+xml,%3Csvg/%3E#a", nil, nil),
    ] as [(String, String?, String?)])
  func useHref(href: String, url: String?, id: String?) {
    let external = SVGUseElement.externalHref(href)
    #expect(external?.url == url)
    #expect(external?.id == id)
  }

  @Test("a loader rebased to a file reads relative URLs from the file, in the same folder")
  func rebased() async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/images/a.png")
    try folder.write("b", at: "docs/b.png")
    let loader = ExternalResourceLoader(
      baseURL: folder.url.appending(path: "docs/image.svg"), folder: folder.url.appending(path: "docs"),
      cache: ExternalResourceCache())
    let file = try #require(loader.resourceURL(ofHref: "images/other.svg"))
    let rebased = loader.rebased(to: file)
    #expect(await rebased.data(forHref: "a.png").map { String(decoding: $0, as: UTF8.self) } == "a")
    #expect(await rebased.data(forHref: "../b.png").map { String(decoding: $0, as: UTF8.self) } == "b")
    #expect(await rebased.data(forHref: "../../outside.png") == nil)
  }

  /// A loader of a document in the folder `docs` that reads the folder, and the network if it's allowed.
  private func loader(
    in folder: Folder, baseURL: URL?? = nil, allowsNetwork: Bool, fetch: FetchCounter = FetchCounter()
  ) -> ExternalResourceLoader {
    ExternalResourceLoader(
      baseURL: baseURL ?? folder.url.appending(path: "docs/image.svg"), folder: folder.url.appending(path: "docs"),
      allowsNetwork: allowsNetwork, cache: ExternalResourceCache(), fetch: fetch.networkFetch)
  }

  @Test("an https URL is read only by a loader that reads the network")
  func network() async throws {
    let folder = try Folder()
    let counter = FetchCounter()
    let files = loader(in: folder, allowsNetwork: false, fetch: counter)
    #expect(files.resourceURL(ofHref: "https://example.test/a.png") == nil)
    #expect(await files.data(forHref: "https://example.test/a.png") == nil)
    #expect(counter.count.withLock { $0 } == 0)
    let network = loader(in: folder, allowsNetwork: true, fetch: counter)
    #expect(
      network.resourceURL(ofHref: " https://example.test/a.png?size=2#layer ")?.absoluteString
        == "https://example.test/a.png?size=2")
    #expect(await network.data(forHref: "https://example.test/a.png") == Data("https://example.test/a.png".utf8))
    // The data is read once.
    #expect(await network.data(forHref: "https://example.test/a.png#layer") != nil)
    #expect(counter.count.withLock { $0 } == 1)
  }

  @Test(
    "URLs of other schemes aren't read from the network",
    arguments: ["http://example.test/a.png", "ftp://example.test/a.png", "https:///a.png", "//example.test/a.png"])
  func otherSchemes(href: String) throws {
    #expect(loader(in: try Folder(), allowsNetwork: true).resourceURL(ofHref: href) == nil)
  }

  @Test("a document of the network reads its relative URLs from the network, and no files")
  func networkDocument() async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/a.png")
    let base = URL(string: "https://example.test/docs/image.svg")
    let network = loader(in: folder, baseURL: base, allowsNetwork: true)
    #expect(network.resourceURL(ofHref: "images/a.png")?.absoluteString == "https://example.test/docs/images/a.png")
    #expect(network.resourceURL(ofHref: "//other.test/a.png")?.absoluteString == "https://other.test/a.png")
    #expect(network.resourceURL(ofHref: folder.url.appending(path: "docs/a.png").absoluteString) == nil)
    #expect(network.resolvedBaseURL == base)
    // Without the network, it reads nothing.
    #expect(loader(in: folder, baseURL: base, allowsNetwork: false).resourceURL(ofHref: "images/a.png") == nil)
  }

  @Test("a document without a base URL reads the network by absolute URLs only")
  func networkWithoutBaseURL() throws {
    let network = loader(in: try Folder(), baseURL: .some(nil), allowsNetwork: true)
    #expect(network.resourceURL(ofHref: "https://example.test/a.png") != nil)
    #expect(network.resourceURL(ofHref: "a.png") == nil)
    #expect(network.resourceURL(ofHref: "file:///a.png") == nil)
  }

  @Test("a loader rebased to a resource of the network reads the network relative to it, and no files")
  func rebasedToNetwork() async throws {
    let folder = try Folder()
    try folder.write("a", at: "docs/a.png")
    let loader = loader(in: folder, allowsNetwork: true)
    let resource = try #require(loader.resourceURL(ofHref: "https://example.test/icons/set.svg"))
    let rebased = loader.rebased(to: resource)
    #expect(rebased.resourceURL(ofHref: "star.png")?.absoluteString == "https://example.test/icons/star.png")
    #expect(rebased.resourceURL(ofHref: folder.url.appending(path: "docs/a.png").absoluteString) == nil)
    // A file that the document of a file refers to reads the files of the folder still.
    let file = try #require(loader.resourceURL(ofHref: "other.svg"))
    #expect(await loader.rebased(to: file).data(forHref: "a.png") == Data("a".utf8))
  }
}
