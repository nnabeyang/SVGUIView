import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that clip paths and masks in an enlarged user space have edges as sharp as they are without the enlargement,
/// and that they clip a much reduced user space.
@MainActor
@Suite("Scaled clip paths and masks")
struct ScaledClipTests {
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

  @Test(
    "a clip path and a mask in a user space reduced 100000 times clip at their edges",
    arguments: [
      (#"<clipPath id="e"><rect width="1000000" height="2000000"/></clipPath>"#, "clip-path"),
      (
        #"<mask id="e" maskUnits="userSpaceOnUse" x="0" y="0" width="2000000" height="2000000">"#
          + #"<rect width="1000000" height="2000000" fill="white"/></mask>"#, "mask"
      ),
    ])
  func reduced(effect: String, attribute: String) async throws {
    // The bitmap of the user space at the scale of the painter would be too large to be made. The edge is at 1000000
    // in the user space of the group, which is 10 in the document.
    let content =
      effect + #"<g transform="scale(0.00001)"><rect width="2000000" height="2000000" fill="blue" "# + attribute
      + #"="url(#e)"/></g>"#
    #expect(try await pixel(content, x: 9, y: 10) == [0, 0, 255, 255])
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }
}
