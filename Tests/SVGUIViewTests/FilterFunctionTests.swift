import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the filter functions of the CSS in `filter` paint as the primitives that they're equal to.
@MainActor
@Suite("Filter functions")
struct FilterFunctionTests {
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

  private func isClose(_ color: [UInt8], _ expected: [UInt8]) -> Bool {
    zip(color, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
  }

  @Test("a blur spreads the element past its edges")
  func blur() async throws {
    let content = #"<rect x="5" y="5" width="10" height="10" fill="red" filter="blur(1)"/>"#
    let edge = try await pixel(content, x: 4, y: 10)
    #expect(edge[3] > 0 && edge[3] < 128, "\(edge)")
    #expect(isClose(try await pixel(content, x: 10, y: 10), [255, 0, 0, 255]))
  }

  @Test("a shadow is the color under the element at the offset, and currentColor where the color is missing")
  func dropShadow() async throws {
    let content = #"<rect width="8" height="8" fill="red" color="blue" filter="drop-shadow(10 10)"/>"#
    #expect(isClose(try await pixel(content, x: 4, y: 4), [255, 0, 0, 255]))
    #expect(isClose(try await pixel(content, x: 14, y: 14), [0, 0, 255, 255]))
    #expect(try await pixel(content, x: 14, y: 4) == [0, 0, 0, 0])
    let translucent = try await pixel(
      #"<rect width="8" height="8" fill="red" filter="drop-shadow(rgba(0, 255, 0, 0.5) 10 10)"/>"#, x: 14, y: 14)
    #expect(isClose(translucent, [0, 128, 0, 128]), "\(translucent)")
  }

  @Test("the color adjustments compute in sRGB")
  func colorAdjustments() async throws {
    func square(_ filter: String) -> String {
      #"<rect width="20" height="20" fill="red" filter=""# + filter + #""/>"#
    }
    // The luminance of red is 0.2126 in sRGB, without converting it to linearRGB.
    #expect(isClose(try await pixel(square("grayscale()"), x: 10, y: 10), [54, 54, 54, 255]))
    #expect(isClose(try await pixel(square("invert()"), x: 10, y: 10), [0, 255, 255, 255]))
    #expect(isClose(try await pixel(square("opacity(0.5)"), x: 10, y: 10), [128, 0, 0, 128]))
    #expect(isClose(try await pixel(square("brightness(0.5)"), x: 10, y: 10), [128, 0, 0, 255]))
  }

  @Test("the filters of a list apply one after another")
  func list() async throws {
    let content =
      #"<filter id="f"><feFlood flood-color="blue"/></filter>"#
      + #"<rect x="5" y="5" width="10" height="10" fill="red" filter="url(#f) invert()"/>"#
    // The flood fills the region of the filter with blue, which the inversion makes yellow.
    #expect(isClose(try await pixel(content, x: 10, y: 10), [255, 255, 0, 255]))
  }

  @Test("a list with an item that isn't valid applies no filter")
  func invalidList() async throws {
    let content = #"<rect width="20" height="20" fill="red" filter="grayscale() hue-rotate(random)"/>"#
    #expect(isClose(try await pixel(content, x: 10, y: 10), [255, 0, 0, 255]))
  }
}
