import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the primitives of filters compute in the color space of their `color-interpolation-filters`.
@MainActor
@Suite("Filter color spaces")
struct FilterColorSpaceTests {
  /// The red, green, blue and alpha components of a pixel of the rendered document, premultiplied, in its user space
  /// of 20 by 20.
  private func pixel(_ content: String, x: Int, y: Int) async throws -> [UInt8] {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot().cgImage)
    let scale = image.width / 20
    var components = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image,
      in: CGRect(x: -x * scale, y: y * scale - image.height + 1, width: image.width, height: image.height))
    return components
  }

  /// Yellow on the left and blue on the right, blurred across the edge between them in the color space.
  private func blurredEdge(_ colorInterpolationFilters: String) -> String {
    #"<filter id="f" "# + colorInterpolationFilters + #"><feGaussianBlur stdDeviation="1"/></filter>"#
      + ##"<g filter="url(#f)"><rect width="10" height="20" fill="yellow"/>"##
      + ##"<rect x="10" width="10" height="20" fill="blue"/></g>"##
  }

  @Test("a blur mixes the colors in linearRGB by default, which is lighter than sRGB between yellow and blue")
  func linearRGBByDefault() async throws {
    // Half yellow and half blue is about 188 in linearRGB, and about 128 in sRGB.
    let linear = try await pixel(blurredEdge(""), x: 10, y: 10)
    #expect(linear[0] > 165 && linear[1] > 165, "\(linear)")
    let explicit = try await pixel(blurredEdge(#"color-interpolation-filters="linearRGB""#), x: 10, y: 10)
    #expect(explicit == linear)
    let sRGB = try await pixel(blurredEdge(#"color-interpolation-filters="sRGB""#), x: 10, y: 10)
    #expect(sRGB[0] < 150 && sRGB[1] < 150, "\(sRGB)")
  }

  @Test("a color that a filter doesn't mix stays the same in either color space")
  func unmixedColor() async throws {
    for space in ["", #"color-interpolation-filters="sRGB""#] {
      // The pixel is five standard deviations from the edges of the yellow, where the blur doesn't reach.
      let color = try await pixel(blurredEdge(space), x: 5, y: 10)
      #expect(color == [255, 255, 0, 255], "\(space): \(color)")
    }
  }
}
