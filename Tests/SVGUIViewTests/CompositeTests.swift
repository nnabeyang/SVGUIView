import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feComposite` composites its first input with its second.
@MainActor
@Suite("Composite")
struct CompositeTests {
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

  /// A red flood on the left 12 units and a blue flood on the right 12 units, which overlap from 8 to 12, composited
  /// with the attributes, red over blue for `over`.
  private func floods(_ attributes: String, filter: String = "") -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20" "# + filter + ">"
      + #"<feFlood flood-color="red" width="12" result="a"/><feFlood flood-color="blue" x="8" result="b"/>"#
      + #"<feComposite in="a" in2="b" "# + attributes + "/></filter>"
      + #"<rect width="20" height="20" filter="url(#f)"/>"#
  }

  /// The colors of a composite on the left, where only the first input is, in the middle, where both are, and on
  /// the right, where only the second is.
  private func colors(_ attributes: String) async throws -> [[UInt8]] {
    var colors = [[UInt8]]()
    for x in [4, 10, 16] {
      colors.append(try await pixel(floods(attributes), x: x, y: 10))
    }
    return colors
  }

  /// Operators and the colors on the left, in the middle and on the right.
  nonisolated private static let operators: [(String, [[UInt8]])] = [
    ("", [[255, 0, 0, 255], [255, 0, 0, 255], [0, 0, 255, 255]]),
    (#"operator="in""#, [[0, 0, 0, 0], [255, 0, 0, 255], [0, 0, 0, 0]]),
    (#"operator="out""#, [[255, 0, 0, 255], [0, 0, 0, 0], [0, 0, 0, 0]]),
    (#"operator="atop""#, [[0, 0, 0, 0], [255, 0, 0, 255], [0, 0, 255, 255]]),
    (#"operator="xor""#, [[255, 0, 0, 255], [0, 0, 0, 0], [0, 0, 255, 255]]),
  ]

  @Test("the operators composite the first input with the second as Porter and Duff do", arguments: operators)
  func operators(attributes: String, expected: [[UInt8]]) async throws {
    let colors = try await colors(attributes)
    #expect(zip(colors, expected).allSatisfy { isClose($0, $1) }, "\(colors)")
  }

  @Test("arithmetic combines the premultiplied components, whose colors don't exceed the alpha")
  func arithmetic() async throws {
    // k2 * red + k3 * blue: half of each where both are, in linearRGB, which is about 188 in sRGB.
    let half = try await colors(#"operator="arithmetic" k2="0.5" k3="0.5""#)
    #expect(isClose(half[1], [188, 0, 188, 255]), "\(half)")
    // Half of the red alone is red at half opacity.
    #expect(isClose(half[0], [128, 0, 0, 128]), "\(half)")
    // k4 adds to every component, and the colors stay within the alpha.
    let offset = try await colors(#"operator="arithmetic" k4="0.5""#)
    #expect(isClose(offset[0], [128, 128, 128, 128]), "\(offset)")
    // In sRGB, half of each is 128.
    let sRGB = try await pixel(
      floods(#"operator="arithmetic" k2="0.5" k3="0.5""#, filter: #"color-interpolation-filters="sRGB""#), x: 10, y: 10)
    #expect(isClose(sRGB, [128, 0, 128, 255]), "\(sRGB)")
  }

  @Test("the result is clipped to the subregion of the primitive")
  func subregion() async throws {
    let content = floods(#"x="0" width="6""#)
    #expect(isClose(try await pixel(content, x: 3, y: 10), [255, 0, 0, 255]))
    #expect(try await pixel(content, x: 16, y: 10) == [0, 0, 0, 0])
  }
}
