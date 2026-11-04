import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feConvolveMatrix` convolves its input with its kernel, whose cells are pixels.
@MainActor
@Suite("Convolve matrix")
struct ConvolveMatrixTests {
  /// The rendered document of the user space of 20 by 20, whose pixels are indexed from the top left.
  private struct Rendering {
    let components: [UInt8]
    let width: Int
    /// The pixels in a unit of the user space.
    let scale: Int

    /// The red, green, blue and alpha components of a pixel, premultiplied.
    func pixel(_ column: Int, _ row: Int) -> [UInt8] {
      let offset = (row * width + column) * 4
      return Array(components[offset..<(offset + 4)])
    }
  }

  private func render(_ content: String) async throws -> Rendering {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot().cgImage)
    var components = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try #require(
      CGContext(
        data: &components, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Rendering(components: components, width: image.width, scale: image.width / 20)
  }

  /// A square from 6 to 14 with a filter of the primitives, whose region is the document.
  private func square(_ primitives: String, fill: String = "red") -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect x="6" y="6" width="8" height="8" fill=""# + fill + #"" filter="url(#f)"/>"#
  }

  private let red: [UInt8] = [255, 0, 0, 255]
  private let transparent: [UInt8] = [0, 0, 0, 0]

  @Test("the kernel is rotated, so that a kernel of 1 0 0 takes the pixel to the right")
  func rotatedColumns() async throws {
    let rendering = try await render(square(#"<feConvolveMatrix order="3 1" kernelMatrix="1 0 0"/>"#))
    let (left, right, middle) = (6 * rendering.scale, 14 * rendering.scale, 10 * rendering.scale)
    #expect(rendering.pixel(left - 1, middle) == red)
    #expect(rendering.pixel(left - 2, middle) == transparent)
    #expect(rendering.pixel(right - 2, middle) == red)
    #expect(rendering.pixel(right - 1, middle) == transparent)
  }

  @Test("the rows of the kernel go down the user space, so that a kernel of 1 0 0 takes the pixel below")
  func rotatedRows() async throws {
    let rendering = try await render(square(#"<feConvolveMatrix order="1 3" kernelMatrix="1 0 0"/>"#))
    let (top, bottom, middle) = (6 * rendering.scale, 14 * rendering.scale, 10 * rendering.scale)
    #expect(rendering.pixel(middle, top - 1) == red)
    #expect(rendering.pixel(middle, top - 2) == transparent)
    #expect(rendering.pixel(middle, bottom - 2) == red)
    #expect(rendering.pixel(middle, bottom - 1) == transparent)
  }

  @Test(
    "the edge mode duplicates, wraps or leaves out the pixels past the input",
    arguments: [("duplicate", [255, 0, 0, 255]), ("wrap", [0, 0, 255, 255]), ("none", [0, 0, 0, 0])] as [(String, [UInt8])])
  func edgeMode(_ mode: String, expected: [UInt8]) async throws {
    // The filter region is the square, blue on its left and red on its right.
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" x="6" y="6" width="8" height="8">"#
      + #"<feConvolveMatrix order="3 1" kernelMatrix="1 0 0" edgeMode=""# + mode + #""/></filter>"#
      + #"<g filter="url(#f)"><rect x="6" y="6" width="4" height="8" fill="blue"/>"#
      + #"<rect x="10" y="6" width="4" height="8" fill="red"/></g>"#
    let rendering = try await render(content)
    let middle = 10 * rendering.scale
    #expect(rendering.pixel(14 * rendering.scale - 1, middle) == expected)
    #expect(rendering.pixel(14 * rendering.scale - 2, middle) == red)
  }

  @Test("preserveAlpha keeps the alpha and convolves the colors without it premultiplied")
  func preserveAlpha() async throws {
    let kernel = #"kernelMatrix="0 0 0 0 2 0 0 0 0" divisor="1""#
    let preserved = try await render(
      square(#"<feConvolveMatrix "# + kernel + #" preserveAlpha="true"/>"#, fill: "rgb(255 0 0 / 0.5)"))
    let middle = 10 * preserved.scale
    let pixel = preserved.pixel(middle, middle)
    #expect(pixel[3] > 100 && pixel[3] < 160)
    #expect(abs(Int(pixel[0]) - Int(pixel[3])) <= 1 && pixel[1] == 0 && pixel[2] == 0)
    let premultiplied = try await render(square(#"<feConvolveMatrix "# + kernel + "/>", fill: "rgb(255 0 0 / 0.5)"))
    #expect(premultiplied.pixel(middle, middle) == red)
  }

  @Test("the bias is added to the alpha, and the bias times the alpha to the colors")
  func bias() async throws {
    let rendering = try await render(square(#"<feConvolveMatrix kernelMatrix="0 0 0 0 1 0 0 0 0" bias="1"/>"#))
    #expect(rendering.pixel(2 * rendering.scale, 2 * rendering.scale) == [255, 255, 255, 255])
  }

  @Test("a kernel that doesn't have as many numbers as the order passes the input through")
  func passThrough() async throws {
    for attributes in [#"order="3 3" kernelMatrix="1 2""#, #"order="0" kernelMatrix="1""#] {
      let rendering = try await render(square("<feConvolveMatrix " + attributes + "/>"))
      #expect(rendering.pixel(10 * rendering.scale, 10 * rendering.scale) == red)
      #expect(rendering.pixel(6 * rendering.scale - 1, 10 * rendering.scale) == transparent)
    }
  }

  @Test("a target out of the kernel is transparent black", arguments: [#"targetX="3""#, #"targetY="-1""#])
  func targetOutOfKernel(_ attributes: String) async throws {
    let rendering = try await render(
      square(#"<feConvolveMatrix kernelMatrix="0 0 0 0 1 0 0 0 0" "# + attributes + "/>"))
    #expect(rendering.components.allSatisfy { $0 == 0 })
  }
}
