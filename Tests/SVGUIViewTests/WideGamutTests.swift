import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that colors outside sRGB are rendered in Display P3 on a screen of a wide gamut.
@MainActor
@Suite("Wide gamut")
struct WideGamutTests {
  private let rect = CGRect(x: 0, y: 0, width: 10, height: 10)

  /// A document of 10 by 10 painted with a paint, which can refer to the definitions.
  private func view(fill: String, definitions: String = "") -> SVGUIView {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">\#(definitions)
        <rect width="10" height="10" fill="\#(fill)"/>
      </svg>
      """#
    return SVGUIView(frame: rect, data: Data(svg.utf8))
  }

  /// The red, green, blue and alpha of the pixel in the middle of an image, in a color space.
  private func middle(of image: CGImage, in name: CFString) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let space = try #require(CGColorSpace(name: name))
    let context = try #require(
      CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    return bytes
  }

  @Test("a color outside sRGB is rendered in Display P3 on a screen of a wide gamut")
  func displayP3() async throws {
    let image = try await view(fill: "color(display-p3 1 0 0)").snapshot(
      rect: rect, at: .zero, scale: 1, wideGamut: true)
    #expect(image.colorSpace?.name == CGColorSpace.displayP3)
    #expect(try middle(of: image, in: CGColorSpace.displayP3) == [255, 0, 0, 255])
  }

  @Test("a color outside sRGB is clamped to sRGB on a screen of sRGB")
  func sRGBScreen() async throws {
    let image = try await view(fill: "color(display-p3 1 0 0)").snapshot(
      rect: rect, at: .zero, scale: 1, wideGamut: false)
    #expect(image.colorSpace?.name != CGColorSpace.displayP3)
    #expect(try middle(of: image, in: CGColorSpace.sRGB) == [255, 0, 0, 255])
  }

  @Test("a document of colors in sRGB is rendered in device RGB, as before, on a screen of a wide gamut")
  func sRGBDocument() async throws {
    let image = try await view(fill: "rgb(10 200 30)").snapshot(rect: rect, at: .zero, scale: 1, wideGamut: true)
    #expect(image.colorSpace?.name != CGColorSpace.displayP3)
    #expect(try middle(of: image, in: CGColorSpace.sRGB) == [10, 200, 30, 255])
  }

  @Test("a gradient keeps its stops outside sRGB")
  func gradient() async throws {
    let gradient = #"""
      <linearGradient id="g">
        <stop stop-color="color(display-p3 0 1 0)"/><stop offset="1" stop-color="color(display-p3 0 1 0)"/>
      </linearGradient>
      """#
    let image = try await view(fill: "url(#g)", definitions: gradient).snapshot(
      rect: rect, at: .zero, scale: 1, wideGamut: true)
    #expect(try middle(of: image, in: CGColorSpace.displayP3) == [0, 255, 0, 255])
  }
}
