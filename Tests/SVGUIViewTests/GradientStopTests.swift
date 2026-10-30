import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the colors of gradients are at the offsets of their stops, in the bands that a reflected gradient
/// reverses too.
@MainActor
@Suite("Gradient stops")
struct GradientStopTests {
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

  /// A rectangle that covers the document with a gradient of the kind with the attributes, which is red at 0, lime at
  /// 0.25 and blue at 1.
  private func gradient(_ kind: String, _ attributes: String) -> String {
    #"<\#(kind) id="g" gradientUnits="userSpaceOnUse" spreadMethod="reflect" "# + attributes + ">"
      + #"<stop offset="0" stop-color="red"/><stop offset="0.25" stop-color="lime"/>"#
      + #"<stop offset="1" stop-color="blue"/></\#(kind)><rect width="20" height="20" fill="url(#g)"/>"#
  }

  @Test("a reflected linear gradient has its colors at the reflected offsets")
  func reflectedLinearGradient() async throws {
    // The center of the pixel is at 1.75 of the gradient, which reflects to 0.25.
    let color = try await pixel(gradient("linearGradient", #"x1="0" x2="10""#), x: 17, y: 10)
    #expect(color[1] > 200 && color[0] < 60 && color[2] < 60, "\(color)")
  }

  @Test("a reflected radial gradient has its colors at the reflected offsets")
  func reflectedRadialGradient() async throws {
    // The center of the pixel is at 1.7 of the gradient, which reflects to 0.3.
    let color = try await pixel(gradient("radialGradient", #"cx="10" cy="10" r="5""#), x: 18, y: 9)
    #expect(color[1] > 170 && color[0] < 60, "\(color)")
  }

  @Test("stops at the same offset change the color there")
  func stopsAtTheSameOffset() async throws {
    let content =
      #"<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="20">"#
      + #"<stop offset="0" stop-color="red"/><stop offset="0.5" stop-color="red"/>"#
      + #"<stop offset="0.5" stop-color="blue"/><stop offset="1" stop-color="blue"/></linearGradient>"#
      + #"<rect width="20" height="20" fill="url(#g)"/>"#
    let left = try await pixel(content, x: 9, y: 10)
    let right = try await pixel(content, x: 10, y: 10)
    #expect(left[0] > 245 && left[2] < 10, "\(left)")
    #expect(right[2] > 245 && right[0] < 10, "\(right)")
  }
}
