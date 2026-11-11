import Foundation

/// Reads the resources that documents reference by `https` URLs.
///
/// The requests carry nothing of the app: the session keeps no cookies, uses no stored credentials and caches
/// nothing, so that a document doesn't reach what the app is signed in to. A redirection to a URL that isn't an
/// `https` URL isn't followed, and a response that isn't a success, or is larger than the limit, isn't read.
package struct NetworkFetch: Sendable {
  package enum Failure: Error, Equatable {
    /// The URL isn't an `https` URL.
    case unsupportedScheme
    /// The response isn't a success, which has a status from 200 to 299.
    case status(Int)
    /// The resource is larger than the limit.
    case tooLarge
  }

  /// The largest resource that's read, in bytes.
  package static let defaultLimit = 64 * 1024 * 1024

  /// The session of the process, which reads the resources of all documents.
  package static let shared = NetworkFetch()

  private let session: URLSession
  private let limit: Int

  /// - Parameters:
  ///   - configuration: The configuration of the session, which tests give the protocols that answer in place of
  ///     the network. The cookies, the credentials and the cache are turned off in it.
  ///   - limit: The largest resource that's read, in bytes.
  package init(configuration: URLSessionConfiguration = .ephemeral, limit: Int = NetworkFetch.defaultLimit) {
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration, delegate: RedirectionPolicy(), delegateQueue: nil)
    self.limit = limit
  }

  /// The data of the resource at an `https` URL. Cancelling the task stops the request.
  package func data(at url: URL) async throws -> Data {
    guard url.scheme?.lowercased() == "https" else { throw Failure.unsupportedScheme }
    let (bytes, response) = try await session.bytes(from: url)
    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
      throw Failure.status(status)
    }
    guard response.expectedContentLength <= Int64(limit) else { throw Failure.tooLarge }
    var data = Data()
    if response.expectedContentLength > 0 {
      data.reserveCapacity(Int(response.expectedContentLength))
    }
    for try await byte in bytes {
      guard data.count < limit else { throw Failure.tooLarge }
      data.append(byte)
    }
    return data
  }
}

/// Follows the redirections to `https` URLs only.
private final class RedirectionPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    request.url?.scheme?.lowercased() == "https" ? request : nil
  }
}
