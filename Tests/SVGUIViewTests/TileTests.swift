import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feTile` repeats the subregion of its input.
@MainActor
@Suite("Tile")
struct TileTests {
  /// A red square in the top left quarter with a filter of the primitives, whose region is the document.
  private func square(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect width="10" height="10" fill="red" filter="url(#f)"/>"#
  }

  private let blue: [UInt8] = [0, 0, 255, 255]
  private let clear: [UInt8] = [0, 0, 0, 0]

  @Test("a tile of 8 by 6 with a blue square of 4 in its top left corner repeats in x and y")
  func repeats() async throws {
    let content = square(
      #"<feFlood flood-color="blue" x="0" y="0" width="4" height="4"/><feOffset x="0" y="0" width="8" height="6"/><feTile/>"#)
    #expect(try await pixel(content, x: 1, y: 1) == blue)
    #expect(try await pixel(content, x: 5, y: 1) == clear)
    #expect(try await pixel(content, x: 9, y: 1) == blue)
    #expect(try await pixel(content, x: 13, y: 1) == clear)
    #expect(try await pixel(content, x: 1, y: 5) == clear)
    #expect(try await pixel(content, x: 1, y: 7) == blue)
    #expect(try await pixel(content, x: 17, y: 13) == blue)
    #expect(try await pixel(content, x: 17, y: 17) == clear)
  }

  @Test("the tiles start at the origin of the subregion of the input, and repeat before it too")
  func origin() async throws {
    let content = square(
      #"<feFlood flood-color="blue" x="3" y="3" width="2" height="2"/><feOffset x="3" y="3" width="4" height="4"/><feTile/>"#)
    #expect(try await pixel(content, x: 3, y: 3) == blue)
    #expect(try await pixel(content, x: 5, y: 5) == clear)
    #expect(try await pixel(content, x: 7, y: 7) == blue)
    #expect(try await pixel(content, x: 0, y: 0) == blue)
    #expect(try await pixel(content, x: 1, y: 1) == clear)
  }

  @Test("the tiles are clipped to the subregion of the tile")
  func subregion() async throws {
    let content = square(
      #"<feFlood flood-color="blue" x="0" y="0" width="2" height="2"/><feTile width="10" height="20"/>"#)
    #expect(try await pixel(content, x: 5, y: 15) == blue)
    #expect(try await pixel(content, x: 15, y: 5) == clear)
  }

  @Test("a tile outside the filter region draws nothing")
  func outside() async throws {
    let content = square(#"<feFlood flood-color="blue" x="-5" y="-5" width="3" height="3"/><feOffset/><feTile/>"#)
    #expect(try await pixel(content, x: 1, y: 1) == clear)
    #expect(try await pixel(content, x: 10, y: 10) == clear)
  }

  @Test("a tile of a named result repeats that result")
  func namedResult() async throws {
    let content = square(
      #"<feFlood flood-color="blue" x="0" y="0" width="2" height="2" result="a"/>"#
        + #"<feFlood flood-color="lime" x="0" y="0" width="20" height="20"/><feTile in="a"/>"#)
    #expect(try await pixel(content, x: 13, y: 17) == blue)
  }
}
