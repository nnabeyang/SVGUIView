import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that groups, svg elements and use elements draw their content with their properties applied.
@MainActor
@Suite("Containers")
struct ContainerTests {
  private static let lime: [UInt8] = [0, 255, 0, 255]
  private static let clear: [UInt8] = [0, 0, 0, 0]

  /// The red, green, blue and alpha components of a pixel of the rendered document, premultiplied, in its user space
  /// of 20 by 20.
  private func pixel(_ svg: String, x: Int, y: Int) async throws -> [UInt8] {
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

  private func document(_ content: String) -> String {
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
  }

  /// A mask that shows the left half of the document.
  private static let leftHalf = #"<mask id="m"><rect width="10" height="20" fill="white"/></mask>"#

  @Test("a group or an svg element with display none draws nothing")
  func displayNone() async throws {
    let svg = document(
      #"""
      <g display="none"><rect width="10" height="20" fill="lime"/></g>
      <svg display="none"><rect x="10" width="10" height="20" fill="lime"/></svg>
      """#)
    #expect(try await pixel(svg, x: 5, y: 10) == Self.clear)
    #expect(try await pixel(svg, x: 15, y: 10) == Self.clear)
  }

  @Test("a group, an svg element and a use element are masked")
  func masks() async throws {
    for content in [
      #"<g mask="url(#m)"><rect width="20" height="20" fill="lime"/></g>"#,
      #"<svg width="20" height="20" mask="url(#m)"><rect width="20" height="20" fill="lime"/></svg>"#,
      ##"<defs><rect id="r" width="20" height="20" fill="lime"/></defs><use href="#r" mask="url(#m)"/>"##,
    ] {
      let svg = document(Self.leftHalf + content)
      #expect(try await pixel(svg, x: 5, y: 10) == Self.lime, "\(content)")
      #expect(try await pixel(svg, x: 15, y: 10) == Self.clear, "\(content)")
    }
  }

  @Test("the mask of a group applies once to its children composited together")
  func groupMaskAppliesOnce() async throws {
    let svg = document(
      #"""
      <mask id="m"><rect width="20" height="20" fill="#808080"/></mask>
      <g mask="url(#m)"><rect width="20" height="20" fill="red"/><rect width="20" height="20" fill="lime"/></g>
      """#)
    let pixel = try await pixel(svg, x: 10, y: 10)
    // Masking each child would leave some of the red rectangle under the lime one.
    #expect(pixel[0] < 4)
    #expect(abs(Int(pixel[1]) - 128) < 8)
    #expect(abs(Int(pixel[3]) - 128) < 8)
  }

  @Test("the root svg element and a nested one composite their content with their opacity")
  func svgOpacity() async throws {
    for svg in [
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" opacity="0.5"><rect width="20" height="20" fill="lime"/></svg>"#,
      document(#"<svg width="20" height="20" opacity="0.5"><rect width="20" height="20" fill="lime"/></svg>"#),
    ] {
      let pixel = try await pixel(svg, x: 10, y: 10)
      #expect(abs(Int(pixel[1]) - 128) < 8, "\(pixel)")
      #expect(abs(Int(pixel[3]) - 128) < 8, "\(pixel)")
    }
  }
}
