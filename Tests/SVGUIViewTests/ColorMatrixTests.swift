import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feColorMatrix` multiplies the colors of its input by its matrix.
@MainActor
@Suite("Color matrix")
struct ColorMatrixTests {
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

  /// A square of a color with a `feColorMatrix` of the attributes.
  private func square(_ fill: String, _ attributes: String, filter: String = "") -> String {
    #"<filter id="f" "# + filter + #"><feColorMatrix "# + attributes + #"/></filter>"#
      + #"<rect width="20" height="20" "# + fill + #" filter="url(#f)"/>"#
  }

  private func isClose(_ color: [UInt8], _ expected: [UInt8]) -> Bool {
    zip(color, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
  }

  @Test("saturate makes gray from the luminance in linearRGB by default, and in sRGB where the filter says")
  func saturate() async throws {
    // The luminance of red is 0.213, which is about 127 in sRGB from linearRGB, and 54 in sRGB.
    let linear = try await pixel(square(#"fill="red""#, #"type="saturate" values="0""#), x: 10, y: 10)
    #expect(isClose(linear, [127, 127, 127, 255]), "\(linear)")
    let sRGB = try await pixel(
      square(#"fill="red""#, #"type="saturate" values="0""#, filter: #"color-interpolation-filters="sRGB""#),
      x: 10, y: 10)
    #expect(isClose(sRGB, [54, 54, 54, 255]), "\(sRGB)")
  }

  @Test("a matrix multiplies the colors without the alpha premultiplied")
  func unpremultipliedColors() async throws {
    // The matrix swaps red and green of a red at half opacity.
    let swapped = try await pixel(
      square(#"fill="red" fill-opacity="0.5""#, #"values="0 1 0 0 0 1 0 0 0 0 0 0 1 0 0 0 0 0 1 0""#), x: 10, y: 10)
    #expect(isClose(swapped, [0, 128, 0, 128]), "\(swapped)")
    // The fifth number of a row adds to the component, here to green.
    let offset = try await pixel(
      square(#"fill="red" fill-opacity="0.5""#, #"values="1 0 0 0 0 0 1 0 0 1 0 0 1 0 0 0 0 0 1 0""#), x: 10, y: 10)
    #expect(isClose(offset, [128, 128, 0, 128]), "\(offset)")
  }

  @Test("luminanceToAlpha makes a black whose alpha is the luminance")
  func luminanceToAlpha() async throws {
    let white = try await pixel(square(#"fill="white""#, #"type="luminanceToAlpha""#), x: 10, y: 10)
    #expect(isClose(white, [0, 0, 0, 255]), "\(white)")
    // The luminance of blue is 0.0721 in linearRGB.
    let blue = try await pixel(square(#"fill="blue""#, #"type="luminanceToAlpha""#), x: 10, y: 10)
    #expect(isClose(blue, [0, 0, 0, 18]), "\(blue)")
  }

  @Test("the result is clipped to the subregion of the primitive")
  func subregion() async throws {
    let content = square(#"fill="red""#, #"type="hueRotate" values="0" x="0" width="10""#)
    #expect(isClose(try await pixel(content, x: 5, y: 10), [255, 0, 0, 255]))
    #expect(try await pixel(content, x: 15, y: 10) == [0, 0, 0, 0])
  }
}
