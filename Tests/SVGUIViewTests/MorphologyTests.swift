import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feMorphology` thins and fattens its input.
@MainActor
@Suite("Morphology")
struct MorphologyTests {
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

  /// A red square from 6 to 14 with a filter of the primitives, whose region is the document.
  private func square(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect x="6" y="6" width="8" height="8" fill="red" filter="url(#f)"/>"#
  }

  @Test("erode thins the input by the radius")
  func erode() async throws {
    let content = square(#"<feMorphology radius="2"/>"#)
    #expect(try await pixel(content, x: 10, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 8, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 7, y: 10) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 10, y: 12) == [0, 0, 0, 0])
  }

  @Test("dilate fattens the input by the radius")
  func dilate() async throws {
    let content = square(#"<feMorphology operator="dilate" radius="2"/>"#)
    #expect(try await pixel(content, x: 4, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 15, y: 15) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 3, y: 10) == [0, 0, 0, 0])
  }

  @Test("the radii in x and in y can differ")
  func radii() async throws {
    let content = square(#"<feMorphology operator="dilate" radius="3 1"/>"#)
    #expect(try await pixel(content, x: 3, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 10, y: 4) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 10, y: 5) == [255, 0, 0, 255])
  }

  @Test("a negative radius or radii that are both 0 leave the input as it is", arguments: ["0", "-1", "2 -1", "0 0", ""])
  func ineffective(radius: String) async throws {
    let content = square(#"<feMorphology operator="dilate" radius=""# + radius + #""/>"#)
    #expect(try await pixel(content, x: 6, y: 6) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 5, y: 10) == [0, 0, 0, 0])
  }

  @Test("a radius of 0 doesn't change the input in its direction")
  func zeroRadius() async throws {
    let content = square(#"<feMorphology operator="dilate" radius="2 0"/>"#)
    #expect(try await pixel(content, x: 4, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 10, y: 5) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 10, y: 6) == [255, 0, 0, 255])
  }

  @Test("erode takes transparent black outside the filter region")
  func filterRegion() async throws {
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20"><feMorphology radius="2"/></filter>"#
      + #"<rect width="20" height="20" fill="red" filter="url(#f)"/>"#
    #expect(try await pixel(content, x: 10, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 2, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 1, y: 10) == [0, 0, 0, 0])
  }

  @Test("the result is clipped to the subregion of the primitive")
  func subregion() async throws {
    let content = square(#"<feMorphology operator="dilate" radius="2" width="10"/>"#)
    #expect(try await pixel(content, x: 9, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 11, y: 10) == [0, 0, 0, 0])
  }
}
