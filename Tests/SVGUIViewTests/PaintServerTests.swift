import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests the transforms and the color spaces of gradients and patterns.
@MainActor
@Suite("Gradients and patterns")
struct PaintServerTests {
  @Test("a gradient with linearRGB interpolates its colors in linear sRGB")
  func linearRGB() async throws {
    func middle(_ interpolation: String) async throws -> [UInt8] {
      try await pixel(
        #"<linearGradient id="g" gradientUnits="userSpaceOnUse" x2="20" color-interpolation="\#(interpolation)">"#
          + #"<stop offset="0" stop-color="white"/><stop offset="1" stop-color="blue"/></linearGradient>"#
          + #"<rect width="20" height="20" fill="url(#g)"/>"#, x: 10, y: 10)
    }
    // Half way from white to blue is 0.5 of red in linear sRGB, which is about 188 in sRGB, and 128 in sRGB.
    let linear = try await middle("linearRGB")
    let srgb = try await middle("sRGB")
    #expect(linear[0] > 170 && linear[0] < 200, "\(linear)")
    #expect(srgb[0] > 110 && srgb[0] < 145, "\(srgb)")
  }

  @Test("a gradient or a pattern that its transform makes flat paints the fallback, or nothing")
  func flatTransforms() async throws {
    let stops = #"<stop offset="0" stop-color="red"/><stop offset="1" stop-color="red"/>"#
    let gradient = try await pixel(
      #"<linearGradient id="g" gradientTransform="scale(0)">\#(stops)</linearGradient>"#
        + #"<rect width="20" height="20" fill="url(#g) lime"/>"#, x: 10, y: 10)
    let radial = try await pixel(
      #"<radialGradient id="g" gradientTransform="matrix(0 0 0 0 0 0)">\#(stops)</radialGradient>"#
        + #"<rect width="20" height="20" fill="url(#g) lime"/>"#, x: 10, y: 10)
    let pattern = try await pixel(
      #"<pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" patternTransform="matrix(1 1 0 0 0 0)">"#
        + #"<rect width="20" height="20" fill="red"/></pattern><rect width="20" height="20" fill="url(#p) lime"/>"#,
      x: 10, y: 10)
    let withoutFallback = try await pixel(
      #"<linearGradient id="g" gradientTransform="scale(0)">\#(stops)</linearGradient>"#
        + #"<rect width="20" height="20" fill="url(#g)"/>"#, x: 10, y: 10)
    #expect(gradient == [0, 255, 0, 255], "\(gradient)")
    #expect(radial == [0, 255, 0, 255], "\(radial)")
    #expect(pattern == [0, 255, 0, 255], "\(pattern)")
    #expect(withoutFallback[3] == 0, "\(withoutFallback)")
  }
}
