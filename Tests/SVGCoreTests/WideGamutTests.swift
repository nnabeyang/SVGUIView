import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SVGCore

/// The render tree of a document of 100 by 100 with the content.
private func tree(_ content: String) async throws -> RenderTree {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet))
  return try #require(
    await RenderTreeBuilder(base: base, viewPort: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1).build(fit: fit))
}

/// A data URL of a PNG image of a pixel in a color space.
private func pngURL(in space: CFString) throws -> String {
  let colorSpace = try #require(CGColorSpace(name: space))
  let context = try #require(
    CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
  let image = try #require(context.makeImage())
  let data = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return "data:image/png;base64," + (data as Data).base64EncodedString()
}

@Suite("Wide gamut")
struct WideGamutTests {
  @Test(
    "a tree that paints a color outside sRGB uses a wide gamut",
    arguments: [
      #"<rect width="10" height="10" fill="color(display-p3 1 0 0)"/>"#,
      #"<rect width="10" height="10" fill="none" stroke="oklch(0.7 0.3 145)"/>"#,
      #"<linearGradient id="g"><stop stop-color="red"/><stop offset="1" stop-color="color(rec2020 0 1 0)"/></linearGradient>"#
        + #"<rect width="10" height="10" fill="url(#g)"/>"#,
      #"<g><rect width="10" height="10" fill="color(display-p3 0 1 0)"/></g>"#,
      ##"<defs><rect id="r" width="10" height="10" fill="color(display-p3 0 0 1)"/></defs><use href="#r"/>"##,
      #"<svg width="50" height="50"><rect width="10" height="10" fill="color(display-p3 1 0 0)"/></svg>"#,
    ])
  func wideColors(content: String) async throws {
    #expect(try await tree(content).usesWideGamut)
  }

  @Test(
    "a tree that paints colors in sRGB, or colors outside it only into bitmaps of sRGB, doesn't use a wide gamut",
    arguments: [
      #"<rect width="10" height="10" fill="red" stroke="color(display-p3 1 1 1)"/>"#,
      #"<rect width="10" height="10" fill="lab(50 20 20)"/>"#,
      #"<filter id="f"><feOffset/></filter><rect width="10" height="10" fill="color(display-p3 1 0 0)" filter="url(#f)"/>"#,
      #"<mask id="m"><rect width="10" height="10" fill="color(display-p3 1 0 0)"/></mask>"#
        + #"<rect width="10" height="10" mask="url(#m)"/>"#,
    ])
  func sRGBColors(content: String) async throws {
    #expect(try await !tree(content).usesWideGamut)
  }

  @Test("a tree that paints an image of a wide gamut uses a wide gamut, and one of sRGB doesn't")
  func images() async throws {
    func image(_ space: CFString) throws -> String {
      #"<image width="10" height="10" href=""# + (try pngURL(in: space)) + #""/>"#
    }
    #expect(try await tree(image(CGColorSpace.displayP3)).usesWideGamut)
    #expect(try await !tree(image(CGColorSpace.sRGB)).usesWideGamut)
  }
}
