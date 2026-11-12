import CoreGraphics
import SnapshotTesting
import Testing
import UIKit

/// Tests that the snapshot tests find colors outside sRGB that are clamped to sRGB.
@MainActor
@Suite
struct WideGamutSnapshotTests {
  /// An image of 4 by 4 pixels filled with a color, in a color space.
  private func image(red: CGFloat, green: CGFloat, blue: CGFloat, in name: CFString) throws -> UIImage {
    let space = try #require(CGColorSpace(name: name))
    let context = try #require(
      CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(try #require(CGColor(colorSpace: space, components: [red, green, blue, 1])))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return UIImage(cgImage: try #require(context.makeImage()))
  }

  /// The red of Display P3 and the red of sRGB, which is the red of Display P3 clamped to sRGB.
  private func reds() throws -> (displayP3: UIImage, sRGB: UIImage) {
    (
      try image(red: 1, green: 0, blue: 0, in: CGColorSpace.displayP3),
      try image(red: 1, green: 0, blue: 0, in: CGColorSpace.sRGB)
    )
  }

  @Test("the screen that the snapshots are rendered for shows colors outside sRGB")
  func screen() {
    #expect(UIScreen.main.traitCollection.displayGamut == .P3)
  }

  @Test("a reference image keeps its colors outside sRGB through a PNG")
  func png() throws {
    let snapshotting = Snapshotting<UIImage, UIImage>.wideGamutImage(precision: 0.999, perceptualPrecision: 0.98)
    let red = try reds().displayP3
    let read = try #require(snapshotting.diffing.fromData(snapshotting.diffing.toData(red)).cgImage)
    #expect(read.colorSpace?.isWideGamutRGB == true)
    #expect(snapshotting.diffing.diffV2(red, UIImage(cgImage: read)) == nil)
  }

  @Test("a color outside sRGB doesn't match the color clamped to sRGB")
  func clamped() throws {
    let (displayP3, sRGB) = try reds()
    let snapshotting = Snapshotting<UIImage, UIImage>.wideGamutImage(precision: 0.999, perceptualPrecision: 0.98)
    #expect(snapshotting.diffing.diffV2(displayP3, sRGB) != nil)
    #expect(snapshotting.diffing.diffV2(sRGB, displayP3) != nil)
    // The comparison of swift-snapshot-testing alone draws both images into sRGB, where they match.
    let image = Snapshotting<UIImage, UIImage>.image(precision: 0.999, perceptualPrecision: 0.98)
    #expect(image.diffing.diffV2(displayP3, sRGB) == nil)
  }

  @Test("the same images match, in Display P3 and in sRGB")
  func same() throws {
    let snapshotting = Snapshotting<UIImage, UIImage>.wideGamutImage(precision: 0.999, perceptualPrecision: 0.98)
    let (displayP3, sRGB) = try reds()
    #expect(snapshotting.diffing.diffV2(displayP3, displayP3) == nil)
    #expect(snapshotting.diffing.diffV2(sRGB, sRGB) == nil)
  }
}
