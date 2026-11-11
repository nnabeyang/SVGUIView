import Foundation
import Synchronization
import Testing

@testable import SVGCore

/// Answers the requests of a session in place of the network, by the path of the URL.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
  /// The requests that the sessions sent, by the hosts of their URLs, which each test names differently.
  static let requests = Mutex<[String: [URLRequest]]>([:])

  static func requests(to host: String) -> [URLRequest] {
    requests.withLock { $0[host] ?? [] }
  }

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url, let host = url.host else { return }
    Self.requests.withLock { $0[host, default: []].append(request) }
    func respond(_ status: Int, headers: [String: String] = [:], body: Data = Data()) {
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }
    switch url.path {
    case "/green":
      respond(200, headers: ["Set-Cookie": "id=1; Path=/"], body: Data("green".utf8))
    case "/missing":
      respond(404, body: Data("not found".utf8))
    case "/large":
      respond(200, headers: ["Content-Length": "10"], body: Data(repeating: 1, count: 10))
    case "/large-unknown":
      respond(200, body: Data(repeating: 1, count: 10))
    case "/to-http", "/to-https":
      let target = URL(string: url.path == "/to-http" ? "http://\(host)/green" : "https://\(host)/green")!
      let response = HTTPURLResponse(
        url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
      client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
      // A session that doesn't follow the redirection takes the response as it is.
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
    default:
      // "/never" doesn't answer.
      break
    }
  }

  override func stopLoading() {}
}

@Suite("Reading the resources of the network")
struct NetworkFetchTests {
  private func fetch(limit: Int = NetworkFetch.defaultLimit) -> NetworkFetch {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return NetworkFetch(configuration: configuration, limit: limit)
  }

  /// A URL of a host that only the test that calls it uses.
  private func url(_ path: String, scheme: String = "https", host: String = #function) -> URL {
    URL(string: "\(scheme)://\(host.filter(\.isLetter).lowercased()).test/\(path)")!
  }

  @Test("the data of a response that's a success is read")
  func success() async throws {
    #expect(try await fetch().data(at: url("green")) == Data("green".utf8))
  }

  @Test("a response that isn't a success isn't read")
  func failure() async throws {
    await #expect(throws: NetworkFetch.Failure.status(404)) { try await fetch().data(at: url("missing")) }
  }

  @Test("an http URL isn't read")
  func http() async throws {
    let url = url("green", scheme: "http")
    await #expect(throws: NetworkFetch.Failure.unsupportedScheme) { try await fetch().data(at: url) }
    #expect(StubProtocol.requests(to: try #require(url.host)).isEmpty)
  }

  @Test("a redirection to an https URL is followed, and one to an http URL isn't")
  func redirection() async throws {
    #expect(try await fetch().data(at: url("to-https")) == Data("green".utf8))
    let url = url("to-http")
    await #expect(throws: NetworkFetch.Failure.status(302)) { try await fetch().data(at: url) }
    let requests = StubProtocol.requests(to: try #require(url.host))
    #expect(!requests.contains { $0.url?.scheme == "http" })
  }

  @Test("a resource larger than the limit isn't read, with a length or without one")
  func limit() async throws {
    await #expect(throws: NetworkFetch.Failure.tooLarge) { try await fetch(limit: 9).data(at: url("large")) }
    await #expect(throws: NetworkFetch.Failure.tooLarge) { try await fetch(limit: 9).data(at: url("large-unknown")) }
    #expect(try await fetch(limit: 10).data(at: url("large")).count == 10)
    #expect(try await fetch(limit: 10).data(at: url("large-unknown")).count == 10)
  }

  @Test("the cookies of a response aren't kept or sent")
  func cookies() async throws {
    let fetch = fetch()
    let url = url("green")
    _ = try await fetch.data(at: url)
    _ = try await fetch.data(at: url)
    let requests = StubProtocol.requests(to: try #require(url.host))
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
  }

  @Test("cancelling the task stops the request", .timeLimit(.minutes(1)))
  func cancellation() async throws {
    let fetch = fetch()
    let url = url("never")
    let task = Task { try await fetch.data(at: url) }
    let host = try #require(url.host)
    while StubProtocol.requests(to: host).isEmpty {
      try await Task.sleep(for: .milliseconds(5))
    }
    task.cancel()
    let result = await task.result
    #expect(throws: (any Error).self) { try result.get() }
  }
}
