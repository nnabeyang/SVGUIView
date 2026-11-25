import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests the regions that masks, clip paths and filters cover, and how masks mask.
@MainActor
@Suite("The regions of masks, clip paths and filters")
struct MaskAndClipRegionTests {
  private static let lime: [UInt8] = [0, 255, 0, 255]

  @Test("the region of a mask is in fractions of the bounding box by default, and in user space for userSpaceOnUse")
  func maskUnits() async throws {
    let white = #"<rect width="20" height="20" fill="white"/>"#
    let fractions = try await pixel(
      #"<mask id="m" x="0" y="0" width="1" height="1">\#(white)</mask>"#
        + #"<rect x="5" y="5" width="10" height="10" fill="lime" mask="url(#m)"/>"#, x: 10, y: 10)
    #expect(fractions == Self.lime, "\(fractions)")
    let userSpace = """
      <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="8" height="20">\(white)</mask>\
      <rect x="5" y="5" width="10" height="10" fill="lime" mask="url(#m)"/>
      """
    let inside = try await pixel(userSpace, x: 6, y: 10)
    let outside = try await pixel(userSpace, x: 10, y: 10)
    #expect(inside == Self.lime, "\(inside)")
    #expect(outside[3] == 0, "\(outside)")
  }

  @Test("the default region of a mask goes 10% past the bounding box, over the stroke there")
  func defaultMaskRegion() async throws {
    let content = """
      <mask id="m"><rect width="20" height="20" fill="white"/></mask>\
      <rect x="5" y="5" width="10" height="10" fill="none" stroke="lime" stroke-width="6" mask="url(#m)"/>
      """
    // The region is 4 to 16, and the stroke 2 to 18.
    let inRegion = try await pixel(content, x: 4, y: 10)
    let outside = try await pixel(content, x: 2, y: 10)
    #expect(inRegion == Self.lime, "\(inRegion)")
    #expect(outside[3] == 0, "\(outside)")
  }

  @Test("a mask of the alpha type masks with the alpha of its content, and of the luminance type with its luminance")
  func maskType() async throws {
    func masked(_ type: String) async throws -> [UInt8] {
      try await pixel(
        #"<mask id="m" mask-type="\#(type)"><rect width="20" height="20" fill="black"/></mask>"#
          + #"<rect width="20" height="20" fill="lime" mask="url(#m)"/>"#, x: 10, y: 10)
    }
    let alpha = try await masked("alpha")
    let luminance = try await masked("luminance")
    #expect(alpha == Self.lime, "\(alpha)")
    #expect(luminance[3] == 0, "\(luminance)")
    let styled = try await pixel(
      #"<mask id="m" style="mask-type: alpha"><rect width="20" height="20" fill="black"/></mask>"#
        + #"<rect width="20" height="20" fill="lime" mask="url(#m)"/>"#, x: 10, y: 10)
    #expect(styled == Self.lime, "\(styled)")
  }

  @Test("a clip path clips what an element draws outside its bounds, such as a marker, as its shapes clip it")
  func clipOutsideBounds() async throws {
    let content = """
      <clipPath id="c" clipPathUnits="userSpaceOnUse"><rect width="20" height="20"/></clipPath>\
      <marker id="k" markerWidth="8" markerHeight="8" refX="4" refY="4" markerUnits="userSpaceOnUse">\
      <rect width="8" height="8" fill="lime"/></marker>\
      <path d="M10 10 H16 V16 H10 Z" fill="black" marker-start="url(#k)" clip-path="url(#c)"/>
      """
    // The marker is 6 to 14, and the path 10 to 16.
    let marker = try await pixel(content, x: 7, y: 7)
    #expect(marker == Self.lime, "\(marker)")
  }

  @Test("the default region of a filter of userSpaceOnUse is in percentages of the viewport")
  func userSpaceFilterRegion() async throws {
    let pixel = try await pixel(
      #"<filter id="f" filterUnits="userSpaceOnUse"><feOffset/></filter>"#
        + #"<rect x="9" y="9" width="2" height="2" fill="none" stroke="lime" stroke-width="10" filter="url(#f)"/>"#,
      x: 5, y: 5)
    #expect(pixel == Self.lime, "\(pixel)")
  }
}
