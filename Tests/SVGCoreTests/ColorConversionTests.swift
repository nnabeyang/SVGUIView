import Foundation
import Testing

@testable import SVGCore

@Suite("Color conversions")
struct ColorConversionTests {
  /// Colors of sRGB, from 0 to 1.
  private static let colors: [ColorConversion.Vector] = [
    (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.2, 0.4, 0.6), (0.9, 0.8, 0.1), (0.5, 0.5, 0.5), (0, 0, 0), (1, 1, 1),
  ]

  private static let spaces: [ColorMixSpace] = [
    .sRGB, .sRGBLinear, .displayP3, .a98RGB, .proPhotoRGB, .rec2020, .lab, .oklab, .xyz, .xyzD50, .xyzD65, .hsl, .hwb,
    .lch, .oklch,
  ]

  @Test("a color of sRGB converted to a color space and back is the same color", arguments: spaces)
  func roundTrip(space: ColorMixSpace) {
    for color in Self.colors {
      // A color without a hue has the hue 0, which doesn't change it.
      let components = space.components(ofSRGB: color).map { $0 ?? 0 }
      let back = space.sRGB(ofComponents: components)
      let differences = [back.0 - color.0, back.1 - color.1, back.2 - color.2].map(abs)
      #expect(differences.allSatisfy { $0 < 1e-4 }, "\(space) \(color): \(back)")
    }
  }
}
