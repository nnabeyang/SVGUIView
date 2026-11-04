import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feMorphology` thins and fattens its input.
@MainActor
@Suite("Morphology")
struct MorphologyTests {
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
