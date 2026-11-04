import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// Tests that the filter regions are limited to what shows, with the distance that their primitives reach.
@Suite("Limiting filter regions to what shows")
struct FilterRegionLimitTests {
  /// The filtered node of a rectangle with a filter of the primitives, whose region is 0 to 100 in x and y.
  private func node(_ primitives: String) async throws -> FilteredNode {
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">"# + primitives
      + #"</filter><rect width="100" height="100" filter="url(#f)"/>"#
    return try #require(try await filteredNodes(content, scale: 2).first)
  }

  @Test("a region that shows whole stays as it is")
  func wholeRegion() async throws {
    let filtered = try await node(#"<feOffset dx="5"/>"#)
    let limited = filtered.limited(toVisible: CGRect(x: -10, y: -10, width: 200, height: 200), scale: 2)
    #expect(limited.effectRect == filtered.effectRect)
  }

  @Test(
    "a region that shows in part is limited to what shows with its size on each side, the reach of the primitives and a pixel"
  )
  func partOfRegion() async throws {
    let filtered = try await node(#"<feOffset dx="5" dy="3"/><feGaussianBlur stdDeviation="2"/>"#)
    let limited = filtered.limited(toVisible: CGRect(x: 40, y: 40, width: 10, height: 10), scale: 2)
    // The size adds 10, the offset reaches 5 and 3, the blur 6, and a pixel is half a unit, on the pixels from the
    // origin.
    #expect(limited.effectRect == CGRect(x: 18.5, y: 20.5, width: 53, height: 49))
  }

  @Test("a region within what shows with its size on each side stays as it is")
  func nearRegion() async throws {
    let filtered = try await node(#"<feOffset dx="5"/>"#)
    let limited = filtered.limited(toVisible: CGRect(x: 20, y: 20, width: 60, height: 60), scale: 2)
    #expect(limited.effectRect == filtered.effectRect)
  }

  @Test("a region that doesn't show has no area")
  func hiddenRegion() async throws {
    let filtered = try await node(#"<feOffset dx="5"/>"#)
    let limited = filtered.limited(toVisible: CGRect(x: 500, y: 500, width: 10, height: 10), scale: 2)
    #expect(limited.effectRect.isEmpty)
  }

  @Test(
    "a filter that takes pixels from anywhere in its region isn't limited",
    arguments: [
      #"<feTile/>"#, #"<feConvolveMatrix order="3" kernelMatrix="0 0 0 0 1 0 0 0 0" edgeMode="wrap"/>"#,
    ])
  func unlimited(primitives: String) async throws {
    let filtered = try await node(primitives)
    let limited = filtered.limited(toVisible: CGRect(x: 40, y: 40, width: 10, height: 10), scale: 2)
    #expect(limited.effectRect == filtered.effectRect)
  }
}
