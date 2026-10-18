import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("SVGUIView")
struct SVGUIViewTests {
  private func makeView(_ svg: String, timeoutDuration: Duration = .seconds(10)) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: timeoutDuration)
    return view
  }

  private func makeImage() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return try #require(context.makeImage())
  }

  @Test("a snapshot is the rendered document")
  func takeSnapshot() async throws {
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#)
    let image = try await view.takeSnapshot()
    // The image is rendered at the screen's scale.
    let pixels = Int(20 * UIScreen.main.scale)
    #expect(image.cgImage?.width == pixels)
    #expect(image.cgImage?.height == pixels)
  }

  @Test("a snapshot of a document without a root svg element throws missingRootElement")
  func takeSnapshotWithoutRootElement() async {
    let view = makeView(#"<svg xmlns="http://www.example.org/notsvg"><rect width="20" height="20"/></svg>"#)
    await #expect(throws: SVGRenderingError.missingRootElement) {
      try await view.takeSnapshot()
    }
  }

  @Test(
    "a snapshot of a rectangle without a width or a height throws zeroSizedRect",
    arguments: [
      CGRect(x: 0, y: 0, width: 0, height: 20),
      CGRect(x: 0, y: 0, width: 20, height: 0),
    ])
  func takeSnapshotOfZeroSizedRect(rect: CGRect) async {
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#)
    await #expect(throws: SVGRenderingError.zeroSizedRect) {
      try await view.takeSnapshot(rect: rect)
    }
  }

  @Test("a snapshot of a view without a size throws zeroSizedRect")
  func takeSnapshotOfZeroSizedView() async {
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20"/></svg>"#)
    view.frame = .zero
    await #expect(throws: SVGRenderingError.zeroSizedRect) {
      try await view.takeSnapshot()
    }
  }

  @Test("a snapshot that takes longer than the timeout throws timedOut")
  func takeSnapshotTimesOut() async {
    // Rendering checks for cancellation between elements, so many groups make it stop soon after the timeout.
    let groups = String(repeating: #"<g><rect width="20" height="20"/></g>"#, count: 10_000)
    let view = makeView(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">\#(groups)</svg>"#, timeoutDuration: .zero)
    await #expect(throws: SVGRenderingError.timedOut) {
      try await view.takeSnapshot()
    }
  }

  @Test("a rendering that timed out keeps the image that the view shows")
  func showKeepsImageWhenTimedOut() throws {
    let view = makeView(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
    let image = try makeImage()
    view.show(.success(image))
    view.show(.failure(.timedOut))
    let contents = try #require(view.layer.contents)
    #expect(contents as AnyObject === image)
  }

  @Test(
    "a rendering that has nothing to show clears the image that the view shows",
    arguments: [SVGRenderingError.missingRootElement, .zeroSizedRect])
  func showClearsImage(error: SVGRenderingError) throws {
    let view = makeView(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
    view.show(.success(try makeImage()))
    view.show(.failure(error))
    #expect(view.layer.contents == nil)
  }
}
