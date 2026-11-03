import CoreGraphics

// The colors are in the color spaces of the UIColor initializers that they replace, so that renderings stay
// the same.
extension CGColor {
  private static let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!
  private static let extendedGray = CGColorSpace(name: CGColorSpace.extendedGray)!

  /// Opaque black, as `UIColor.black`.
  static let opaqueBlack = CGColor(colorSpace: extendedGray, components: [0, 1])!
  /// Transparent black, as `UIColor.clear`.
  static let transparent = CGColor(colorSpace: extendedGray, components: [0, 0])!

  /// A color in the extended sRGB color space, as `UIColor(red:green:blue:alpha:)`. Components outside 0
  /// to 1 are kept.
  static func extendedSRGB(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> CGColor {
    CGColor(colorSpace: extendedSRGB, components: [red, green, blue, alpha])!
  }

  /// Whether the color is outside sRGB: one of the extended sRGB, whose red, green or blue is outside 0 to 1 by more
  /// than half a step of 8 bits.
  package var isOutsideSRGB: Bool {
    // The colors outside sRGB are made in the extended sRGB space of `extendedSRGB(red:green:blue:alpha:)`, which
    // is compared by identity, since comparing names is slower.
    guard colorSpace === Self.extendedSRGB, let components, components.count == 4 else { return false }
    let tolerance = SVGColor.sRGBTolerance
    return components.dropLast().contains { $0 < -tolerance || $0 > 1 + tolerance }
  }
}
