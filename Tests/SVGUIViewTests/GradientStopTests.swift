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
