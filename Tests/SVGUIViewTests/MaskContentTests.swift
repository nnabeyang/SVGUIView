import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the children of masks are drawn as any other elements.
@MainActor
@Suite("Mask content")
struct MaskContentTests {
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

  @Test("a group and the stroke of a line in a mask show the masked element")
  func groupAndLine() async throws {
    let content = ##"""
      <mask id="m">
        <g><rect width="10" height="10" fill="white"/></g>
        <line x1="0" y1="15" x2="20" y2="15" stroke="white" stroke-width="4"/>
      </mask>
      <rect width="20" height="20" fill="lime" mask="url(#m)"/>
      """##
    #expect(try await pixel(content, x: 5, y: 5) == [0, 255, 0, 255])
    #expect(try await pixel(content, x: 15, y: 15) == [0, 255, 0, 255])
    #expect(try await pixel(content, x: 15, y: 5) == [0, 0, 0, 0])
  }
}
