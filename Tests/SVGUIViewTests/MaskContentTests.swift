import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the children of masks are drawn as any other elements.
@MainActor
@Suite("Mask content")
struct MaskContentTests {
  @Test("a group and the stroke of a line in a mask show the masked element")
  func groupAndLine() async throws {
    let content = ##"""
      <mask id="m">
        <g><rect width="10" height="10" fill="white"/></g>
        <line x1="0" y1="15" x2="20" y2="15" stroke="white" stroke-width="4"/>
      </mask>
      <rect width="20" height="20" fill="lime" mask="url(#m)"/>
      """##
    #expect(try await pixel(content, x: 5, y: 5) == [0, 255, 0, 255])
    #expect(try await pixel(content, x: 15, y: 15) == [0, 255, 0, 255])
    #expect(try await pixel(content, x: 15, y: 5) == [0, 0, 0, 0])
  }
}
