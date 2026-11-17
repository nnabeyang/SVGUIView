import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that clip paths and masks keep their edges on elements whose bounds have fractions of pixels.
@MainActor
@Suite("Clip paths and masks of fractional bounds")
struct FractionalBoundsMaskingTests {
  /// A rectangle of a fractional width, clipped or masked to the 9 units on the left.
  nonisolated static let documents = [
    #"<clipPath id="c"><rect width="9" height="20"/></clipPath>"#
      + #"<rect width="10.1" height="20" fill="lime" clip-path="url(#c)"/>"#,
    #"<mask id="m"><rect width="9" height="20" fill="white"/></mask>"#
      + #"<rect width="10.1" height="20" fill="lime" mask="url(#m)"/>"#,
  ]

  @Test(
    "the edge of a clip path or a mask on an element of fractional bounds stays where it is",
    arguments: documents, [1, 3])
  func edges(content: String, scale: Int) async throws {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(document(content).utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    let image = try #require(try await view.takeSnapshot(scale: CGFloat(scale)).cgImage)
    let rendering = Rendering(components: try pixels(of: image), width: image.width, scale: scale)
    // The last column of pixels inside the edge is covered entirely, and the first one outside it isn't at all.
    #expect(rendering.pixel(9 * scale - 1, 10) == [0, 255, 0, 255])
    #expect(rendering.pixel(9 * scale, 10) == [0, 0, 0, 0])
  }

  /// A rectangle that starts and ends between the pixels of a viewBox reduced to 0.8, clipped or masked at 12.5 units,
  /// which is 10 points.
  nonisolated static let reducedDocuments = [
    #"<clipPath id="c"><rect width="12.5" height="25"/></clipPath>"#
      + #"<rect x="0.17" width="20.3" height="25" fill="lime" clip-path="url(#c)"/>"#,
    #"<mask id="m"><rect width="12.5" height="25" fill="white"/></mask>"#
      + #"<rect x="0.17" width="20.3" height="25" fill="lime" mask="url(#m)"/>"#,
  ]

  @Test(
    "the edge of a clip path or a mask in a reduced user space is as sharp as the edge of a shape",
    arguments: reducedDocuments, [1, 3])
  func reducedEdges(content: String, scale: Int) async throws {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 25 25">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    let image = try #require(try await view.takeSnapshot(scale: CGFloat(scale)).cgImage)
    let rendering = Rendering(components: try pixels(of: image), width: image.width, scale: scale)
    #expect(rendering.pixel(10 * scale - 1, 10) == [0, 255, 0, 255])
    #expect(rendering.pixel(10 * scale, 10) == [0, 0, 0, 0])
  }
}
