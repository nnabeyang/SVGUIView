import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feImage` draws an element or an image into its subregion.
@MainActor
@Suite("Image primitive")
struct ImagePrimitiveTests {
  /// A PNG of one red pixel.
  private static let redPixel =
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

  /// A rectangle that covers the document, with a filter of the primitives in sRGB whose region is the document, and
  /// a lime square from 0 to 4 in the definitions.
  private func filtered(_ primitives: String) -> String {
    #"<defs><rect id="r" width="4" height="4" fill="lime"/></defs>"#
      + #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20" color-interpolation-filters="sRGB">"#
      + primitives + #"</filter><rect width="20" height="20" filter="url(#f)"/>"#
  }

  private let lime: [UInt8] = [0, 255, 0, 255]
  private let red: [UInt8] = [255, 0, 0, 255]
  private let transparent: [UInt8] = [0, 0, 0, 0]

  @Test("an element moves to the origin of the subregion")
  func element() async throws {
    let content = filtered(##"<feImage x="5" y="6" href="#r"/>"##)
    #expect(try await pixel(content, x: 6, y: 7) == lime)
    #expect(try await pixel(content, x: 8, y: 9) == lime)
    #expect(try await pixel(content, x: 2, y: 2) == transparent)
    #expect(try await pixel(content, x: 10, y: 11) == transparent)
  }

  @Test("the subregion clips the element")
  func clippedElement() async throws {
    let content = filtered(##"<feImage x="5" y="5" width="2" height="2" href="#r"/>"##)
    #expect(try await pixel(content, x: 5, y: 5) == lime)
    #expect(try await pixel(content, x: 8, y: 8) == transparent)
  }

  @Test("an image of a data URL is placed in the subregion by its preserveAspectRatio")
  func picture() async throws {
    let content = filtered(#"<feImage width="10" href=""# + Self.redPixel + #""/>"#)
    #expect(try await pixel(content, x: 5, y: 10) == red)
    #expect(try await pixel(content, x: 5, y: 2) == transparent)
    #expect(try await pixel(content, x: 15, y: 10) == transparent)
    let stretched = filtered(#"<feImage width="10" preserveAspectRatio="none" href=""# + Self.redPixel + #""/>"#)
    #expect(try await pixel(stretched, x: 5, y: 2) == red)
  }
}
