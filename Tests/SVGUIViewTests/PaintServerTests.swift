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
}
