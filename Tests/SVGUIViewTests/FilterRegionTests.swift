import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the filters of elements far away that a transform brings into the view, and of huge regions, are
/// drawn.
@MainActor
@Suite("Filter regions")
struct FilterRegionTests {
  private let lime: [UInt8] = [0, 255, 0, 255]

  @Test("the filter of an element far away that a transform brings into the view is drawn")
  func transformedElement() async throws {
    let content =
      #"<filter id="f"><feOffset dx="1"/></filter>"#
      + #"<g transform="translate(-1995 0)"><rect x="2000" y="5" width="10" height="10" fill="lime" filter="url(#f)"/></g>"#
    #expect(try await pixel(content, x: 10, y: 10) == lime)
    #expect(try await pixel(content, x: 5, y: 10) == [0, 0, 0, 0])
  }

  @Test("the filter of a huge region is drawn")
  func hugeRegion() async throws {
    let content =
      #"<filter id="f" filterUnits="userSpaceOnUse" x="-50000" y="-50000" width="100000" height="100000">"#
      + #"<feFlood flood-color="lime"/></filter><rect width="20" height="20" filter="url(#f)"/>"#
    #expect(try await pixel(content, x: 1, y: 1) == lime)
    #expect(try await pixel(content, x: 18, y: 18) == lime)
  }
}
