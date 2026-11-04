import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feOffset` moves the input that `in` names, clipped by its subregion.
@MainActor
@Suite("Offset")
struct OffsetTests {
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
