import Foundation
import Synchronization

/// Reads the files that a document references by URLs relative to the document, within a folder that it's allowed
/// to read.
///
/// A loader reads only files: a URL that isn't a file URL, a reference to an element of the document, a data URL and
/// a file outside the folder aren't read. The folder and the file are compared after their symbolic links are
/// resolved, so that neither `..` nor a link leads outside the folder.
package struct ExternalResourceLoader: Sendable {
  /// Reads the data at a file URL.
  package typealias Fetch = @Sendable (URL) async throws -> Data

  /// The URL that relative URLs are resolved against, which is the URL of the document.
  let baseURL: URL?
  /// The folder whose files are read, with its symbolic links resolved, or `nil` if no file is read.
  private let folder: URL?
  /// The data of the files that have been read.
  private let cache: ExternalResourceCache
  private let fetch: Fetch

  /// A loader that reads nothing.
  package static let none = ExternalResourceLoader(baseURL: nil, folder: nil, cache: ExternalResourceCache())

  /// - Parameters:
  ///   - baseURL: The URL that relative URLs are resolved against, or `nil` if the document has none, in which case
  ///     nothing is read.
  ///   - folder: The folder whose files are read, or `nil` if no file is read.
  ///   - cache: The data of the files that have been read for the document.
  ///   - fetch: Reads the data at a file URL in the folder.
  package init(
    baseURL: URL?, folder: URL?, cache: ExternalResourceCache,
    fetch: @escaping Fetch = { try Data(contentsOf: $0, options: .mappedIfSafe) }
  ) {
    self.baseURL = baseURL
    self.folder = baseURL == nil ? nil : folder.map(Self.resolved)
    self.cache = cache
    self.fetch = fetch
  }

  /// The URL of the file that an `href` references, resolved against the base URL, if the loader reads it.
  ///
  /// - Returns: The file URL with its symbolic links resolved, or `nil` if the `href` doesn't reference a file, or
  ///   references one outside the folder.
  package func fileURL(ofHref href: String) -> URL? {
    guard let baseURL, let folder else { return nil }
    let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !href.isEmpty, !href.hasPrefix("#"), !href.lowercased().hasPrefix("data:"),
      let absolute = URL(string: href, relativeTo: baseURL)?.absoluteURL, absolute.scheme?.lowercased() == "file",
      var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false)
    else { return nil }
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { return nil }
    let file = Self.resolved(url)
    let folderComponents = folder.pathComponents
    let fileComponents = file.pathComponents
    guard fileComponents.count > folderComponents.count, fileComponents.starts(with: folderComponents) else {
      return nil
    }
    return file
  }

  /// The data of the file that an `href` references, or `nil` if the loader doesn't read it, the file can't be read,
  /// or the task is cancelled.
  ///
  /// A file is read once for the cache, and a file that couldn't be read isn't read again, unless reading it was
  /// cancelled.
  package func data(forHref href: String) async -> Data? {
    guard let url = fileURL(ofHref: href) else { return nil }
    if let cached = cache[url] { return cached }
    let data = try? await fetch(url)
    guard !Task.isCancelled else { return nil }
    cache[url] = .some(data)
    return data
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
