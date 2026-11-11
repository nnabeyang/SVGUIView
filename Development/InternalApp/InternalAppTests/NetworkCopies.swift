import Foundation
import SVGTestSuite

@testable import SVGUIView

/// Reads the resources that the tests refer to by `https` URLs from their copies in the test suite, so that the
/// tests don't read the network.
enum NetworkCopies {
  struct Missing: Error {
    let url: URL
  }

  /// The files of the test suite, and the network, which ``fetch`` answers in place of.
  static var resources: ExternalResources {
    .folder(TestSuite.bundle.bundleURL).allowingNetwork()
  }

  /// Reads a file, or the copy of a resource of the network at `w3c/network/<host>/<path>` in the test suite. A
  /// resource without a copy isn't read.
  static let fetch: @Sendable (URL) async throws -> Data = { url in
    if url.isFileURL {
      return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    guard let host = url.host, !url.path.contains("..") else { throw Missing(url: url) }
    let copy = TestSuite.bundle.bundleURL.appending(path: "w3c/network/\(host)\(url.path)")
    guard FileManager.default.fileExists(atPath: copy.path) else { throw Missing(url: url) }
    return try Data(contentsOf: copy, options: .mappedIfSafe)
  }
}
