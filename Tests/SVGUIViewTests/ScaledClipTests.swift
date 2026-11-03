import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that clip paths and masks in an enlarged user space have edges as sharp as they are without the enlargement.
@MainActor
@Suite("Scaled clip paths and masks")
struct ScaledClipTests {
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

  nonisolated private static let clip = #"<clipPath id="e"><rect width="2.5" height="5"/></clipPath>"#
  nonisolated private static let mask =
    #"<mask id="e" maskUnits="userSpaceOnUse" x="0" y="0" width="5" height="5"><rect width="2.5" height="5" fill="white"/></mask>"#

  @Test(
    "a clip path and a mask in a user space enlarged 4 times have sharp edges",
    arguments: [(clip, "clip-path"), (mask, "mask")])
  func enlarged(effect: String, attribute: String) async throws {
    // The edge is at 2.5 in the user space of the group, which is 10 in the document.
    let content =
      effect + #"<g transform="scale(4)"><rect width="5" height="5" fill="blue" "# + attribute + #"="url(#e)"/></g>"#
    #expect(try await pixel(content, x: 9, y: 10) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }

  @Test("a clip path in a user space that is rotated and enlarged has sharp edges")
  func rotated() async throws {
    // The matrix turns the user space a quarter and enlarges it 4 times, so the edge is at y = 10 in the document.
    let content =
      Self.clip + #"<g transform="matrix(0 4 -4 0 20 0)"><rect width="5" height="5" fill="blue" clip-path="url(#e)"/></g>"#
    #expect(try await pixel(content, x: 10, y: 9) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }

  @Test("an svg element whose viewBox enlarges its content has a sharp clip path")
  func viewBox() async throws {
    let content =
      #"<clipPath id="c"><rect width="5" height="10"/></clipPath>"#
      + #"<svg width="20" height="20" viewBox="0 0 10 10" clip-path="url(#c)"><rect width="10" height="10" fill="blue"/></svg>"#
    #expect(try await pixel(content, x: 9, y: 10) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }
}
