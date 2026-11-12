import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feDisplacementMap` moves the pixels of its input by the components of its map.
@MainActor
@Suite("Displacement map")
struct DisplacementMapTests {
  /// A red square from 6 to 14 with a filter of the primitives, whose region is the document, and whose attributes
  /// are `attributes`.
  private func square(_ primitives: String, attributes: String = "") -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20" "# + attributes + ">"
      + primitives + #"</filter><rect x="6" y="6" width="8" height="8" fill="red" filter="url(#f)"/>"#
  }

  /// A map of a flood, whose result is `map`, followed by a displacement of the source graphic by its red and green.
  private func displaced(map: String, scale: String) -> String {
    #"<feFlood "# + map + #" result="map"/>"#
      + #"<feDisplacementMap in="SourceGraphic" in2="map" scale=""# + scale
      + #"" xChannelSelector="R" yChannelSelector="G"/>"#
  }

  @Test("a map of red moves the input by half the scale to the left and down")
  func uniform() async throws {
    let content = square(displaced(map: #"flood-color="red""#, scale: "8"))
    #expect(try await pixel(content, x: 2, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 9, y: 17) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 1, y: 12) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 10, y: 12) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 4, y: 9) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 4, y: 18) == [0, 0, 0, 0])
  }

  @Test("the components of the map are taken without their alpha premultiplied")
  func semiTransparentMap() async throws {
    let content = square(displaced(map: #"flood-color="red" flood-opacity="0.5""#, scale: "8"))
    #expect(try await pixel(content, x: 2, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 10, y: 12) == [0, 0, 0, 0])
  }

  @Test(
    "a scale of 0 and a map of 0.5 in the color space of the primitive move nothing",
    arguments: [
      (#"flood-color="red""#, "0", ""),
      (#"flood-color="rgb(128, 128, 128)""#, "8", #"color-interpolation-filters="sRGB""#),
    ])
  func nothingMoves(map: String, scale: String, attributes: String) async throws {
    let content = square(displaced(map: map, scale: scale), attributes: attributes)
    #expect(try await pixel(content, x: 6, y: 6) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 13, y: 13) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 5, y: 10) == [0, 0, 0, 0])
    #expect(try await pixel(content, x: 14, y: 10) == [0, 0, 0, 0])
  }

  @Test("a map of 0.5 in sRGB is less than 0.5 in linearRGB, and moves the input")
  func linearMap() async throws {
    let content = square(displaced(map: #"flood-color="rgb(128, 128, 128)""#, scale: "8"))
    // The map is about 0.22 in linearRGB, which moves the input by about 2 to the right and down.
    #expect(try await pixel(content, x: 15, y: 15) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 7, y: 7) == [0, 0, 0, 0])
  }

  @Test("pixels that take pixels outside the input are transparent black")
  func outside() async throws {
    let content = square(displaced(map: #"flood-color="red""#, scale: "60"))
    #expect(try await pixel(content, x: 10, y: 10) == [0, 0, 0, 0])
  }

  @Test("the result is clipped to the subregion of the primitive")
  func subregion() async throws {
    let content = square(
      #"<feDisplacementMap in="SourceGraphic" in2="SourceGraphic" scale="0" width="10"/>"#)
    #expect(try await pixel(content, x: 9, y: 10) == [255, 0, 0, 255])
    #expect(try await pixel(content, x: 11, y: 10) == [0, 0, 0, 0])
  }
}
