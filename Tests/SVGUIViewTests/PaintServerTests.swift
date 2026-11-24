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

  @Test("the transform property of a gradient and a pattern overrides gradientTransform and patternTransform")
  func transformProperty() async throws {
    func gradient(_ attributes: String) async throws -> [UInt8] {
      try await pixel(
        #"<linearGradient id="g" gradientUnits="userSpaceOnUse" x2="20" \#(attributes)>"#
          + #"<stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>"#
          + #"<rect width="20" height="20" fill="url(#g)"/>"#, x: 15, y: 10)
    }
    // Scaled by a half, the gradient ends at 10, and pads blue after it.
    let styled = try await gradient(#"gradientTransform="scale(1)" style="transform: scale(0.5)""#)
    let attribute = try await gradient(#"gradientTransform="scale(0.5)""#)
    // The transform attribute isn't a presentation attribute of a gradient.
    let transformAttribute = try await gradient(#"transform="scale(0.5)""#)
    #expect(styled[0] < 5 && styled[2] > 250, "\(styled)")
    #expect(attribute[0] < 5 && attribute[2] > 250, "\(attribute)")
    #expect(transformAttribute[0] > 40, "\(transformAttribute)")
    let pattern = try await pixel(
      #"<style>pattern { transform: translate(10px, 0) }</style>"#
        + #"<pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse">"#
        + #"<rect width="10" height="20" fill="red"/></pattern><rect width="20" height="20" fill="url(#p)"/>"#,
      x: 15, y: 10)
    #expect(pattern == [255, 0, 0, 255], "\(pattern)")
  }

  @Test("the viewBox of a pattern places its origin at the tile, before patternTransform scales the tile")
  func patternViewBox() async throws {
    // The viewBox starts at 10, where the red half of the content is.
    let origin = try await pixel(
      #"<pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" viewBox="10 0 20 20">"#
        + #"<rect x="10" width="10" height="20" fill="red"/></pattern><rect width="20" height="20" fill="url(#p)"/>"#,
      x: 5, y: 10)
    #expect(origin == [255, 0, 0, 255], "\(origin)")
    // A tile of 10, half red: the viewBox of 40 fits a tile of 20, which the transform scales by a half once.
    let scaled = try await pixel(
      #"<pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" viewBox="0 0 40 40""#
        + #" patternTransform="scale(0.5)"><rect width="20" height="40" fill="red"/></pattern>"#
        + #"<rect width="20" height="20" fill="url(#p)"/>"#, x: 4, y: 4)
    #expect(scaled == [255, 0, 0, 255], "\(scaled)")
  }
}
