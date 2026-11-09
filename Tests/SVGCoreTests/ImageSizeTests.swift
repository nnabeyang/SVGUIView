import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SVGCore

/// The rectangles of the `<image>` elements of a document, and the rectangles where their images are drawn, in
/// document order.
private func images(in content: String) async throws -> [(frame: CGRect, image: CGRect?)] {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .min, yAlign: .min, option: .meet), stretches: false, scales: false
  )
  let tree = try #require(
    await RenderTreeBuilder(base: base, viewPort: CGRect(x: 0, y: 0, width: 400, height: 400), scale: 1).build(fit: fit))
  var found = [(frame: CGRect, image: CGRect?)]()
  func visit(_ node: RenderNode) {
    switch node {
    case .shape(let shape):
      if case .image(let paint, _)? = shape.content, let geometry = shape.geometry {
        found.append((geometry.frame, paint?.rect))
      }
    case .group(let group): group.children.forEach(visit)
    case .viewport(let viewport): viewport.content?.children.forEach(visit)
    case .use(let use): use.instance?.content.map(visit)
    case .filtered: break
    }
  }
  tree.root.map(visit)
  return found
}

/// A data URL of a PNG of a size.
private func pngURL(width: Int, height: Int) throws -> String {
  let context = try #require(
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  let image = try #require(context.makeImage())
  let data = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return "data:image/png;base64," + (data as Data).base64EncodedString()
}

/// A data URL of an SVG image, percent-encoded.
private func svgURL(_ svg: String) -> String {
  "data:image/svg+xml," + (svg.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
}

@Suite("The size of an image element")
struct ImageSizeTests {
  @Test(
    "a width or a height of auto takes the size and the ratio of the image, or the default object size",
    arguments: [
      // A size, a ratio, both or neither, and the width and the height that are given.
      (IntrinsicSize(width: 64, height: 32, ratio: 2), nil, nil, CGSize(width: 64, height: 32)),
      (IntrinsicSize(width: 64, height: 32, ratio: 2), 20, nil, CGSize(width: 20, height: 10)),
      (IntrinsicSize(width: 64, height: 32, ratio: 2), nil, 20, CGSize(width: 40, height: 20)),
      (IntrinsicSize(width: nil, height: nil, ratio: 1), nil, nil, CGSize(width: 150, height: 150)),
      (IntrinsicSize(width: nil, height: nil, ratio: 4), nil, nil, CGSize(width: 300, height: 75)),
      (IntrinsicSize(width: 50, height: nil, ratio: 0.5), nil, nil, CGSize(width: 50, height: 100)),
      (IntrinsicSize(width: 50, height: nil, ratio: nil), nil, nil, CGSize(width: 50, height: 150)),
      (IntrinsicSize(width: nil, height: 40, ratio: nil), nil, nil, CGSize(width: 300, height: 40)),
      (IntrinsicSize(width: nil, height: nil, ratio: nil), 30, nil, CGSize(width: 30, height: 150)),
      (IntrinsicSize(), nil, nil, CGSize(width: 300, height: 150)),
    ] as [(IntrinsicSize, CGFloat?, CGFloat?, CGSize)])
  func resolved(intrinsic: IntrinsicSize, width: CGFloat?, height: CGFloat?, expected: CGSize) {
    #expect(intrinsic.resolved(width: width, height: height) == expected)
  }

  @Test("an image without a width or a height takes the size of its bitmap")
  func bitmap() async throws {
    let png = try pngURL(width: 64, height: 32)
    let found = try await images(
      in: #"<image href="\#(png)" x="8" y="8"/><image href="\#(png)" width="auto" height="16"/>"#
        + #"<image href="\#(png)" width="20"/><image href="\#(png)" width="10" height="10"/>"#)
    #expect(
      found.map(\.frame) == [
        CGRect(x: 8, y: 8, width: 64, height: 32), CGRect(x: 0, y: 0, width: 32, height: 16),
        CGRect(x: 0, y: 0, width: 20, height: 10), CGRect(x: 0, y: 0, width: 10, height: 10),
      ])
  }

  @Test("an SVG image has the size of its root's absolute width and height, and the ratio of its view box")
  func svgImage() async throws {
    let sized = svgURL(#"<svg xmlns="http://www.w3.org/2000/svg" width="50" height="25"/>"#)
    let ratio = svgURL(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"/>"#)
    let percent = svgURL(#"<svg xmlns="http://www.w3.org/2000/svg" width="50%" height="10vh" viewBox="0 0 2 1"/>"#)
    let found = try await images(
      in: #"<image href="\#(sized)"/><image href="\#(ratio)" height="20"/><image href="\#(ratio)"/>"#
        + #"<image href="\#(percent)" width="40"/>"#)
    #expect(
      found.map(\.frame.size) == [
        CGSize(width: 50, height: 25), CGSize(width: 40, height: 20), CGSize(width: 300, height: 150),
        CGSize(width: 40, height: 20),
      ])
  }

  @Test("the fragment of the URL of an SVG image names a view, whose view box replaces the root's")
  func view() async throws {
    let svg = svgURL(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><view id="v" viewBox="0 0 40 10"/></svg>"#)
    let found = try await images(in: #"<image href="\#(svg)#v" width="80"/><image href="\#(svg)#missing" width="80"/>"#)
    #expect(found.map(\.frame.size) == [CGSize(width: 80, height: 20), CGSize(width: 80, height: 80)])
    #expect(found.first?.image == CGRect(x: 0, y: 0, width: 40, height: 10).applying(.init(scaleX: 2, y: 2)))
  }

  @Test("an image that can't be read has the default object size where its size is auto")
  func missing() async throws {
    let found = try await images(in: #"<image href="missing.png"/><image width="10"/>"#)
    #expect(found.map(\.frame.size) == [CGSize(width: 300, height: 150), CGSize(width: 10, height: 150)])
  }
}
