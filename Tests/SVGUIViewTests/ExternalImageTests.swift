import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import SVGUIView

/// A folder with a document `docs/image.svg` that shows a green image file, which is removed when it's released.
///
/// The folder has the same image in the folder of the document, `docs/images/green.png`, and outside it,
/// `green.png`.
private final class DocumentFolder {
  let url: URL
  /// The URL of the document.
  let documentURL: URL
  /// The data of the document.
  let data: Data

  init(href: String = "images/green.png") throws {
    url = FileManager.default.temporaryDirectory.appending(path: "ExternalImages-\(UUID().uuidString)")
    let images = url.appending(path: "docs/images")
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let png = try Self.greenPNG()
    try png.write(to: images.appending(path: "green.png"))
    try png.write(to: url.appending(path: "green.png"))
    documentURL = url.appending(path: "docs/image.svg")
    data = Data(document(#"<image href="\#(href)" width="20" height="20"/>"#).utf8)
    try data.write(to: documentURL)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// A PNG of a green pixel.
  private static func greenPNG() throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }
}

/// Signals that a file is being read.
private final class ReadingSignal: Sendable {
  private let continuation: AsyncStream<Void>.Continuation
  let started: AsyncStream<Void>

  init() {
    (started, continuation) = AsyncStream.makeStream()
  }

  /// Reads nothing until the task is cancelled, which a timeout or the cancellation of the snapshot does.
  var fetch: @Sendable (URL) async throws -> Data {
    { _ in
      self.continuation.yield()
      try await Task.sleep(for: .seconds(600))
      return Data()
    }
  }
}

@MainActor
@Suite("Images in other files")
struct ExternalImageTests {
  /// The components of the pixel at the center of the snapshot of the view, in a view of 20 by 20.
  private func center(of view: SVGUIView, timeout: Duration = patience) async throws -> [UInt8] {
    view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    view.configuration = SVGUIViewConfiguration(
      timeoutDuration: timeout, externalResources: view.configuration.externalResources)
    let image = try #require(try await view.takeSnapshot(scale: 1).cgImage)
    return Rendering(components: try pixels(of: image), width: image.width, scale: 1).pixel(x: 10, y: 10)
  }

  private static let greenPixel: [UInt8] = [0, 255, 0, 255]
  private static let clearPixel: [UInt8] = [0, 0, 0, 0]

  @Test("a document opened from a URL shows the images of the files in its folder")
  func contentsOfURL() async throws {
    let folder = try DocumentFolder()
    let view = try #require(SVGUIView(contentsOf: folder.documentURL))
    #expect(view.baseURL == folder.documentURL)
    #expect(try await center(of: view) == Self.greenPixel)
  }

  @Test("an SVG file is shown as an SVG image")
  func svgFile() async throws {
    let folder = try DocumentFolder(href: "images/green.svg")
    try Data(document(#"<rect width="20" height="20" fill="lime"/>"#).utf8)
      .write(to: folder.url.appending(path: "docs/images/green.svg"))
    let view = SVGUIView(data: folder.data, baseURL: folder.documentURL)
    #expect(try await center(of: view) == Self.greenPixel)
  }

  @Test("a feImage shows the image of a file in the folder of the document")
  func feImage() async throws {
    let folder = try DocumentFolder()
    let filter = #"<filter id="f" x="0" y="0" width="1" height="1"><feImage href="images/green.png" preserveAspectRatio="none"/></filter>"#
    let data = Data(document(filter + #"<rect width="20" height="20" filter="url(#f)"/>"#).utf8)
    #expect(try await center(of: SVGUIView(data: data, baseURL: folder.documentURL)) == Self.greenPixel)
    #expect(try await center(of: SVGUIView(data: data)) == Self.clearPixel)
  }

  @Test("data with a base URL shows the images, and data without one doesn't")
  func dataWithBaseURL() async throws {
    let folder = try DocumentFolder()
    let view = SVGUIView(data: folder.data, baseURL: folder.documentURL)
    #expect(try await center(of: view) == Self.greenPixel)
    // Data that's set has no base URL, even the same data.
    view.data = folder.data
    #expect(view.baseURL == nil)
    #expect(try await center(of: view) == Self.clearPixel)
    await view.setData(folder.data, baseURL: folder.documentURL)
    #expect(view.baseURL == folder.documentURL)
    #expect(try await center(of: view) == Self.greenPixel)
    await view.setData(folder.data)
    #expect(view.baseURL == nil)
    #expect(try await center(of: SVGUIView(data: folder.data)) == Self.clearPixel)
  }

  @Test("the configuration decides the folders whose files are read")
  func configuration() async throws {
    let inside = try DocumentFolder()
    let view = SVGUIView(data: inside.data, baseURL: inside.documentURL)
    view.configuration = SVGUIViewConfiguration(externalResources: .none)
    #expect(try await center(of: view) == Self.clearPixel)

    let outside = try DocumentFolder(href: "../green.png")
    let up = SVGUIView(data: outside.data, baseURL: outside.documentURL)
    #expect(try await center(of: up) == Self.clearPixel)
    up.configuration = SVGUIViewConfiguration(externalResources: .folder(outside.url))
    #expect(try await center(of: up) == Self.greenPixel)
  }

  @Test("changing the files that the configuration reads renders the view again")
  func configurationChange() async throws {
    let folder = try DocumentFolder()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: folder.data, baseURL: folder.documentURL)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    window.addSubview(view)
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { $0 == 255 }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none, externalResources: .none)
    try await waitUntil("The view still shows the image") { green(in: view) == nil }
  }

  @Test("reading a file takes part of the time of a rendering, which times out", .timeLimit(.minutes(1)))
  func timeout() async throws {
    let folder = try DocumentFolder()
    let view = SVGUIView(data: folder.data, baseURL: folder.documentURL)
    let signal = ReadingSignal()
    await #expect(throws: SVGRenderingError.timedOut) {
      try await SVGUIView.$resourceFetch.withValue(signal.fetch) {
        _ = try await center(of: view, timeout: .milliseconds(200))
      }
    }
  }

  @Test("cancelling the task that waits for a snapshot stops reading a file", .timeLimit(.minutes(1)))
  func cancellation() async throws {
    let folder = try DocumentFolder()
    let view = SVGUIView(data: folder.data, baseURL: folder.documentURL)
    view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(600))
    let signal = ReadingSignal()
    let task = SVGUIView.$resourceFetch.withValue(signal.fetch) {
      Task { _ = try await view.takeSnapshot() }
    }
    for await _ in signal.started { break }
    task.cancel()
    let result = await task.result
    #expect(throws: SVGRenderingError.cancelled) { try result.get() }
  }
}
