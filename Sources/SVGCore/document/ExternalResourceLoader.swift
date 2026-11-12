import Foundation
import Synchronization

/// Reads the files that a document references by URLs relative to the document, within a folder that it's allowed
/// to read, and, if it's allowed to, the resources that the document references by `https` URLs.
///
/// A reference to an element of the document, a data URL, a file outside the folder and a URL of another scheme,
/// such as `http`, aren't read. The folder and a file are compared after their symbolic links are resolved, so that
/// neither `..` nor a link leads outside the folder. A file is read only for a document in a file, so that a
/// document of the network doesn't read the files of the device.
package struct ExternalResourceLoader: Sendable {
  /// Reads the data at a file URL or an `https` URL.
  package typealias Fetch = @Sendable (URL) async throws -> Data

  /// The URL that relative URLs are resolved against, which is the URL of the document.
  let baseURL: URL?
  /// The folder whose files are read, with its symbolic links resolved, or `nil` if no file is read.
  private let folder: URL?
  /// Whether the resources at `https` URLs are read.
  private let allowsNetwork: Bool
  /// The data of the files that have been read.
  private let cache: ExternalResourceCache
  private let fetch: Fetch

  /// A loader that reads nothing.
  package static let none = ExternalResourceLoader(baseURL: nil, folder: nil, cache: ExternalResourceCache())

  /// Reads a file from the disk, and a resource at an `https` URL from the network.
  package static let defaultFetch: Fetch = { url in
    url.isFileURL ? try Data(contentsOf: url, options: .mappedIfSafe) : try await NetworkFetch.shared.data(at: url)
  }

  /// - Parameters:
  ///   - baseURL: The URL that relative URLs are resolved against, or `nil` if the document has none, in which case
  ///     no file is read.
  ///   - folder: The folder whose files are read, or `nil` if no file is read.
  ///   - allowsNetwork: Whether the resources at `https` URLs are read.
  ///   - cache: The data of the files that have been read for the document.
  ///   - fetch: Reads the data at a file URL in the folder, or at an `https` URL.
  package init(
    baseURL: URL?, folder: URL?, allowsNetwork: Bool = false, cache: ExternalResourceCache,
    fetch: @escaping Fetch = ExternalResourceLoader.defaultFetch
  ) {
    self.baseURL = baseURL
    self.folder = baseURL?.isFileURL == true ? folder.map(Self.resolved) : nil
    self.allowsNetwork = allowsNetwork
    self.cache = cache
    self.fetch = fetch
  }

  /// The URL of the file or of the resource of the network that an `href` references, resolved against the base
  /// URL, if the loader reads it.
  ///
  /// - Returns: The file URL with its symbolic links resolved, or the `https` URL, without its fragment, or `nil` if
  ///   the `href` references neither, a file outside the folder, or the network when the loader doesn't read it.
  package func resourceURL(ofHref href: String) -> URL? {
    let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !href.isEmpty, !href.hasPrefix("#"), !EmbeddedImage.isDataURL(href),
      let absolute = (baseURL.map { URL(string: href, relativeTo: $0) } ?? URL(string: href))?.absoluteURL,
      var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false)
    else { return nil }
    components.fragment = nil
    switch absolute.scheme?.lowercased() {
    case "https":
      guard allowsNetwork, components.host?.isEmpty == false else { return nil }
      return components.url
    case "file":
      // A file is read only relative to a document in a file, in the folder.
      guard let folder else { return nil }
      components.query = nil
      guard let url = components.url else { return nil }
      let file = Self.resolved(url)
      let folderComponents = folder.pathComponents
      let fileComponents = file.pathComponents
      guard fileComponents.count > folderComponents.count, fileComponents.starts(with: folderComponents) else {
        return nil
      }
      return file
    default:
      return nil
    }
  }

  /// The data of the file that an `href` references, or `nil` if the loader doesn't read it, the file can't be read,
  /// or the task is cancelled.
  ///
  /// A file is read once for the cache, and a file that couldn't be read isn't read again, unless reading it was
  /// cancelled.
  package func data(forHref href: String) async -> Data? {
    guard let url = resourceURL(ofHref: href) else { return nil }
    if let cached = cache[url] { return cached }
    let data = try? await fetch(url)
    guard !Task.isCancelled else { return nil }
    cache[url] = .some(data)
    return data
  }

  /// The URL of the document, as ``resourceURL(ofHref:)`` gives the files and the resources of the network: a file
  /// URL with its symbolic links resolved, or `nil` if it has none.
  package var resolvedBaseURL: URL? {
    baseURL.map { $0.isFileURL ? Self.resolved($0) : $0.absoluteURL }
  }

  /// The loader of a document in a file that this loader read, such as one that a `<use>` element shows: its
  /// relative URLs are relative to the file, and it reads the files of the same folder, into the same cache. The
  /// loader of a document that was read from the network reads no files.
  ///
  /// - Parameter url: The URL of the file, as ``resourceURL(ofHref:)`` gives it.
  package func rebased(to url: URL) -> ExternalResourceLoader {
    ExternalResourceLoader(
      baseURL: url, resolvedFolder: url.isFileURL ? folder : nil, allowsNetwork: allowsNetwork, cache: cache,
      fetch: fetch)
  }

  private init(
    baseURL: URL, resolvedFolder: URL?, allowsNetwork: Bool, cache: ExternalResourceCache, fetch: @escaping Fetch
  ) {
    self.baseURL = baseURL
    folder = resolvedFolder
    self.allowsNetwork = allowsNetwork
    self.cache = cache
    self.fetch = fetch
  }

  /// A file URL with `.` and `..` removed and its symbolic links resolved.
  private static func resolved(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
  }
}

/// The data of the files that have been read for a document, which the renderings of the document share.
package final class ExternalResourceCache: Sendable {
  /// The data of each file, or `nil` for a file that couldn't be read.
  private let files = Mutex<[URL: Data?]>([:])

  package init() {}

  /// The data of a file that has been read, `.some(nil)` if it couldn't be read, or `nil` if it hasn't been read.
  subscript(url: URL) -> Data?? {
    get { files.withLock { $0[url] } }
    set { files.withLock { $0[url] = newValue } }
  }
}
