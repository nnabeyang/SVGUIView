import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that radial gradients are drawn from their focal circles, and repeat by their spread methods.
@MainActor
@Suite("Radial gradients")
struct RadialGradientTests {
  /// The red, green, blue and alpha components of a pixel of the rendered document, premultiplied, in its user space
  /// of 20 by 20.
  private func pixel(_ content: String, x: Int, y: Int) async throws -> [UInt8] {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
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

  /// A rectangle that covers the document with a gradient from red to blue with the attributes.
  private func gradient(_ attributes: String) -> String {
    #"<radialGradient id="g" gradientUnits="userSpaceOnUse" cx="10" cy="10" "# + attributes
      + #"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></radialGradient>"#
      + #"<rect width="20" height="20" fill="url(#g)"/>"#
  }

  @Test("a radial gradient starts at its focal point")
  func focalPoint() async throws {
    let content = gradient(#"r="8" fx="5" fy="10""#)
    let left = try await pixel(content, x: 5, y: 10)
    let right = try await pixel(content, x: 14, y: 10)
    #expect(left[0] > 220 && left[2] < 35, "\(left)")
    #expect(Int(right[0]) < Int(left[0]) - 100, "\(right)")
  }

  @Test("a radial gradient repeats or reflects outside its circle by its spread method")
  func spreadMethods() async throws {
    // Outside the circle of radius 4, 5.5 from the center is past 1 by 0.375.
    let padded = try await pixel(gradient(#"r="4""#), x: 15, y: 10)
    let repeated = try await pixel(gradient(#"r="4" spreadMethod="repeat""#), x: 15, y: 10)
    let reflected = try await pixel(gradient(#"r="4" spreadMethod="reflect""#), x: 15, y: 10)
    #expect(padded[0] < 10 && padded[2] > 245, "\(padded)")
    #expect(repeated[0] > repeated[2], "\(repeated)")
    #expect(reflected[2] > reflected[0], "\(reflected)")
  }
}
