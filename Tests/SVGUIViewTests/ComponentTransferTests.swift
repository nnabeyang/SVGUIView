import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feComponentTransfer` maps the components of its input by the functions of its children.
@MainActor
@Suite("Component transfer")
struct ComponentTransferTests {
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

  /// A square of a color with a `feComponentTransfer` of the functions.
  private func square(_ fill: String, _ functions: String, filter: String = "", primitive: String = "") -> String {
    #"<filter id="f" "# + filter + #"><feComponentTransfer "# + primitive + #">"# + functions
      + #"</feComponentTransfer></filter><rect width="20" height="20" "# + fill + #" filter="url(#f)"/>"#
  }

  private func isClose(_ color: [UInt8], _ expected: [UInt8]) -> Bool {
    zip(color, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
  }

  @Test("a function maps a component in linearRGB by default, and in sRGB where the filter says")
  func colorSpace() async throws {
    // Half of blue is about 188 in sRGB from linearRGB, and 128 in sRGB.
    let half = #"<feFuncB type="linear" slope="0.5"/>"#
    let linear = try await pixel(square(#"fill="blue""#, half), x: 10, y: 10)
    #expect(isClose(linear, [0, 0, 188, 255]), "\(linear)")
    let sRGB = try await pixel(square(#"fill="blue""#, half, filter: #"color-interpolation-filters="sRGB""#), x: 10, y: 10)
    #expect(isClose(sRGB, [0, 0, 128, 255]), "\(sRGB)")
  }

  @Test("the functions map the components without the alpha premultiplied, and the alpha too")
  func unpremultipliedColors() async throws {
    // The tables make a red at half opacity green, and the alpha of 0.5 is in the second step, which is opaque.
    let functions =
      #"<feFuncR type="table" tableValues="0 0"/><feFuncG type="table" tableValues="1 1"/>"#
      + #"<feFuncA type="discrete" tableValues="0 1"/>"#
    let color = try await pixel(square(#"fill="red" fill-opacity="0.5""#, functions), x: 10, y: 10)
    #expect(isClose(color, [0, 255, 0, 255]), "\(color)")
    // Without the alpha premultiplied, the green of the red at half opacity is 0, which the table keeps as 0.
    let kept = try await pixel(
      square(#"fill="red" fill-opacity="0.5""#, #"<feFuncR type="table" tableValues="0 1"/>"#), x: 10, y: 10)
    #expect(isClose(kept, [128, 0, 0, 128]), "\(kept)")
  }

  @Test("the result is clipped to the subregion of the primitive")
  func subregion() async throws {
    let content = square(#"fill="red""#, #"<feFuncR type="identity"/>"#, primitive: #"x="0" width="10""#)
    #expect(isClose(try await pixel(content, x: 5, y: 10), [255, 0, 0, 255]))
    #expect(try await pixel(content, x: 15, y: 10) == [0, 0, 0, 0])
  }
}
