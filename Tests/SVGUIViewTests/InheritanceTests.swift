import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that elements draw with the values that their properties inherit, wherever they're drawn.
@MainActor
@Suite("Inheritance")
struct InheritanceTests {
  private static let lime: [UInt8] = [0, 255, 0, 255]
  private static let clear: [UInt8] = [0, 0, 0, 0]

  /// The red, green, blue and alpha components of a pixel of the rendered document, in its user space of 20 by 20.
  private func pixel(_ svg: String, x: Int, y: Int) async throws -> [UInt8] {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot().cgImage)
    let scale = image.width / 20
    var components = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image,
      in: CGRect(x: -x * scale, y: y * scale - image.height + 1, width: image.width, height: image.height))
    return components
  }

  private func document(_ content: String) -> String {
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
  }

  @Test("an element with a filter inherits the fill of its parent")
  func filteredElementInherits() async throws {
    let svg = document(
      #"""
      <filter id="f"><feOffset dx="0" dy="0"/></filter>
      <g fill="lime"><rect width="20" height="20" filter="url(#f)"/></g>
      """#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("the content of a mask inherits from the mask element")
  func maskContentInherits() async throws {
    let svg = document(
      #"""
      <mask id="m" fill="white"><rect width="20" height="20"/></mask>
      <rect width="20" height="20" fill="lime" mask="url(#m)"/>
      """#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("the content of a pattern inherits from the pattern element")
  func patternContentInherits() async throws {
    let svg = document(
      #"""
      <pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" fill="lime">
        <rect width="20" height="20"/>
      </pattern>
      <rect width="20" height="20" fill="url(#p)"/>
      """#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("the content of a use element inherits from the use element, which style sheets style")
  func useContentInherits() async throws {
    let svg = document(
      #"""
      <style>use { fill: lime; }</style>
      <defs><rect id="r" width="20" height="20"/></defs>
      <use href="#r"/>
      """#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("a use element moves its content by x and y before its transform")
  func useTransformOrder() async throws {
    let svg = document(
      #"""
      <defs><rect id="r" width="5" height="5" fill="lime"/></defs>
      <use href="#r" x="5" transform="scale(2)"/>
      """#)
    #expect(try await pixel(svg, x: 17, y: 2) == Self.lime)
    #expect(try await pixel(svg, x: 7, y: 2) == Self.clear)
  }

  @Test("a use element with a filter draws the group that it references")
  func filteredUse() async throws {
    let svg = document(
      #"""
      <filter id="f" x="0" y="0" width="1" height="1"><feOffset dx="0" dy="0"/></filter>
      <defs><g id="g"><rect width="20" height="20" fill="lime"/></g></defs>
      <use href="#g" filter="url(#f)"/>
      """#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("use elements in the content of a use element can reference the same element")
  func repeatedUseInUse() async throws {
    let svg = document(
      #"""
      <defs>
        <rect id="r" width="10" height="20" fill="lime"/>
        <g id="g"><use href="#r"/><use href="#r" x="10"/></g>
      </defs>
      <use href="#g"/>
      """#)
    #expect(try await pixel(svg, x: 5, y: 10) == Self.lime)
    #expect(try await pixel(svg, x: 15, y: 10) == Self.lime)
  }

  @Test("currentColor is the color of the element itself")
  func currentColorOfElement() async throws {
    let svg = document(#"<circle cx="10" cy="10" r="10" color="lime" fill="currentColor"/>"#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("currentColor in a stop is the color that the stop inherits")
  func currentColorOfStop() async throws {
    let svg = document(
      #"""
      <defs color="lime">
        <linearGradient id="g"><stop offset="0" stop-color="currentColor"/></linearGradient>
      </defs>
      <rect width="20" height="20" fill="url(#g)"/>
      """#)
    #expect(try await pixel(svg, x: 10, y: 10) == Self.lime)
  }

  @Test("fill-opacity applies to the fill that the element inherits")
  func fillOpacityAlone() async throws {
    let svg = document(#"<g fill="lime"><rect width="20" height="20" fill-opacity="0.5"/></g>"#)
    let pixel = try await pixel(svg, x: 10, y: 10)
    #expect(pixel[1] > 100 && pixel[1] < 155)
    #expect(pixel[3] > 100 && pixel[3] < 155)
  }

  @Test("an element that visibility hides isn't drawn, and its children that are visible are")
  func visibility() async throws {
    let svg = document(
      #"""
      <g visibility="hidden" fill="lime">
        <rect width="10" height="20"/>
        <rect x="10" width="10" height="20" visibility="visible"/>
      </g>
      """#)
    #expect(try await pixel(svg, x: 5, y: 10) == Self.clear)
    #expect(try await pixel(svg, x: 15, y: 10) == Self.lime)
  }

  @Test("a stroke width in em is relative to the element's own font size, and it's inherited as a length")
  func strokeWidthInEm() async throws {
    let svg = document(
      #"""
      <g font-size="10" stroke-width="2em" stroke="lime" fill="none">
        <line x1="0" y1="10" x2="20" y2="10" font-size="1"/>
      </g>
      """#)
    // The line is 20 wide, from the font size of the group.
    #expect(try await pixel(svg, x: 10, y: 1) == Self.lime)
  }
}
