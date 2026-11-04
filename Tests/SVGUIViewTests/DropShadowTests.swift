import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feDropShadow` paints a shadow of its input under the input.
@MainActor
@Suite("Drop shadow")
struct DropShadowTests {
  private func isClose(_ color: [UInt8], _ expected: [UInt8]) -> Bool {
    zip(color, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
  }

  /// A red square in the top left quarter with a filter of the primitives, whose region is the document.
  private func square(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect width="10" height="10" fill="red" filter="url(#f)"/>"#
  }

  @Test("the shadow is the flood color at the offset, under the input, in the color that the flood color looks")
  func shadow() async throws {
    let content = square(#"<feDropShadow dx="10" dy="10" stdDeviation="0" flood-color="rgb(0, 128, 0)"/>"#)
    #expect(isClose(try await pixel(content, x: 5, y: 5), [255, 0, 0, 255]))
    // The flood color is painted in linearRGB, and looks as it does in sRGB.
    #expect(isClose(try await pixel(content, x: 15, y: 15), [0, 128, 0, 255]))
    #expect(try await pixel(content, x: 15, y: 5) == [0, 0, 0, 0])
  }

  @Test("the flood opacity makes the shadow translucent, and the shadow is black and blurred by default")
  func defaults() async throws {
    let translucent = try await pixel(
      square(#"<feDropShadow dx="10" dy="10" stdDeviation="0" flood-opacity="0.5"/>"#), x: 15, y: 15)
    #expect(isClose(translucent, [0, 0, 0, 128]), "\(translucent)")
    // The shadow is 2 to the right and below, and blurred by 2, so its edge is past the square and soft.
    let edge = try await pixel(square("<feDropShadow/>"), x: 11, y: 5)
    #expect(edge[3] > 0 && edge[3] < 255 && edge[0] == 0, "\(edge)")
  }

  @Test("a shadow after another primitive is the shadow of its result")
  func afterPrimitive() async throws {
    let content = square(
      #"<feFlood flood-color="blue" x="0" y="0" width="5" height="5"/>"#
        + #"<feDropShadow dx="10" dy="10" stdDeviation="0" flood-color="lime" width="20" height="20"/>"#)
    #expect(isClose(try await pixel(content, x: 2, y: 2), [0, 0, 255, 255]))
    #expect(isClose(try await pixel(content, x: 12, y: 12), [0, 255, 0, 255]))
    // The red square isn't the input, so its shadow doesn't show.
    #expect(try await pixel(content, x: 17, y: 17) == [0, 0, 0, 0])
  }

  @Test("the result is clipped to the subregion, and the shadow before it only to the filter region")
  func subregion() async throws {
    let content = square(#"<feDropShadow dx="10" dy="10" stdDeviation="0" x="10" y="10" width="10" height="10"/>"#)
    #expect(try await pixel(content, x: 5, y: 5) == [0, 0, 0, 0])
    #expect(isClose(try await pixel(content, x: 15, y: 15), [0, 0, 0, 255]))
  }
}
