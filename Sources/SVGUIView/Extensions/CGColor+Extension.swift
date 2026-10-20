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
}
