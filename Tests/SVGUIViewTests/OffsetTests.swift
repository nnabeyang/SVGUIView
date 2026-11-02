import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feOffset` moves the input that `in` names, clipped by its subregion.
@MainActor
@Suite("Offset")
struct OffsetTests {
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

  /// A red square in the top left quarter with a filter of the primitives, whose region is the document.
  private func square(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect width="10" height="10" fill="red" filter="url(#f)"/>"#
  }

  @Test("an offset of the source graphic after a flood moves the element, not the flood")
  func sourceGraphic() async throws {
    let content = square(#"<feFlood flood-color="blue" width="5" height="5"/><feOffset in="SourceGraphic" dx="10" dy="10"/>"#)
    #expect(try await pixel(content, x: 15, y: 15) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 2, y: 2) == [0, 0, 0, 0])
  }

  @Test("an offset of a named result moves that result, in a subregion past those of the primitives before")
  func namedResult() async throws {
    let content = square(
      #"<feFlood flood-color="blue" width="5" height="5" result="a"/><feFlood flood-color="lime" x="10" y="0" width="5" height="5"/>"#
        + #"<feOffset in="a" dx="10" dy="10" width="20" height="20"/>"#)
    #expect(try await pixel(content, x: 12, y: 12) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 12, y: 2) == [0, 0, 0, 0])
  }

  @Test("an offset in the units of the bounding box moves the element into a region in the user space past the viewBox")
  func boundingBoxPastViewBox() async throws {
    // The region is 30 wide, more than 1.2 times the viewBox, and the square moves 2 times its size to 10.
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" primitiveUnits="objectBoundingBox" x="-10" y="-10" width="30" height="30">"#
      + #"<feOffset dx="2" dy="2"/></filter><rect width="5" height="5" fill="blue" filter="url(#f)"/>"#
    #expect(try await pixel(content, x: 14, y: 14) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 2, y: 2) == [0, 0, 0, 0])
  }

  @Test("the subregion of an offset is that of its input by default, which clips the moved input")
  func defaultSubregion() async throws {
    let content = square(#"<feFlood flood-color="blue" width="10" height="10"/><feOffset dx="5" dy="5"/>"#)
    #expect(try await pixel(content, x: 7, y: 7) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 12, y: 12) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 2, y: 2) == [0, 0, 0, 0])
  }

  @Test("an offset without in moves the result of the primitive before")
  func previousResult() async throws {
    let content = square(#"<feFlood flood-color="blue" width="20" height="20"/><feOffset dx="10" dy="10"/>"#)
    #expect(try await pixel(content, x: 2, y: 2) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 15, y: 15) == [0, 0, 255, 255])
  }
}
