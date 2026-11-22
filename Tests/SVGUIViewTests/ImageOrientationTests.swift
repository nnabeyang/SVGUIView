import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import SVGUIView

/// Tests that a bitmap is drawn in the orientation that its metadata gives, as UIKit draws it, unless
/// `image-orientation` is `none`.
@MainActor
@Suite("Image orientation")
struct ImageOrientationTests {
  private nonisolated static let orientations: [CGImagePropertyOrientation] = [
    .up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left,
  ]

  /// The middles of the quarters of the square of 16 by 16 at the origin.
  private static let quarters = [(4, 4), (12, 4), (4, 12), (12, 12)]

  /// An image of 32 by 16 with a red, a green, a blue and a yellow quarter, from the top left, with an orientation
  /// in its metadata.
  private func encodedImage(orientation: CGImagePropertyOrientation, type: UTType) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 32 * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // The context is drawn from the bottom up.
    let colors: [(CGFloat, CGFloat, CGFloat, CGRect)] = [
      (1, 0, 0, CGRect(x: 0, y: 8, width: 16, height: 8)), (0, 1, 0, CGRect(x: 16, y: 8, width: 16, height: 8)),
      (0, 0, 1, CGRect(x: 0, y: 0, width: 16, height: 8)), (1, 1, 0, CGRect(x: 16, y: 0, width: 16, height: 8)),
    ]
    for (red, green, blue, rect) in colors {
      context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
      context.fill(rect)
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
      kCGImagePropertyOrientation: orientation.rawValue, kCGImageDestinationLossyCompressionQuality: 1,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }

  /// An `<image>` of data stretched to the square of 16 by 16 at the origin, with the attributes.
  private func image(_ data: Data, type: UTType, _ attributes: String = "") -> String {
    let url = "data:\(type.preferredMIMEType ?? "image/png");base64,\(data.base64EncodedString())"
    return #"<image width="16" height="16" preserveAspectRatio="none" href="\#(url)" "# + attributes + "/>"
  }

  /// The colors of the middles of the quarters of an image that UIKit draws stretched to 16 by 16, in the orientation
  /// that its metadata gives.
  private func expectedQuarters(of data: Data) throws -> [[UInt8]] {
    let image = try #require(UIImage(data: data))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    let drawn = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { _ in
      image.draw(in: CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    let cgImage = try #require(drawn.cgImage)
    let components = try pixels(of: cgImage)
    return Self.quarters.map { x, y in
      let offset = (y * cgImage.width + x) * 4
      return Array(components[offset..<(offset + 4)])
    }
  }

  private func isClose(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 24 }
  }

  @Test("a bitmap is drawn in the orientation of its metadata, as UIKit draws it", arguments: orientations)
  func oriented(orientation: CGImagePropertyOrientation) async throws {
    for type in [UTType.png, .jpeg] {
      let data = try encodedImage(orientation: orientation, type: type)
      let expected = try expectedQuarters(of: data)
      let rendering = try await render(image(data, type: type))
      let actual = Self.quarters.map { rendering.pixel(x: $0.0, y: $0.1) }
      #expect(zip(actual, expected).allSatisfy(isClose), "\(type) \(orientation.rawValue): \(actual) \(expected)")
    }
  }

  @Test("a bitmap is drawn as its pixels are stored where image-orientation is none", arguments: orientations)
  func none(orientation: CGImagePropertyOrientation) async throws {
    let data = try encodedImage(orientation: orientation, type: .png)
    let expected = try expectedQuarters(of: encodedImage(orientation: .up, type: .png))
    for content in [
      image(data, type: .png, #"style="image-orientation: none""#),
      #"<g style="image-orientation: none">"# + image(data, type: .png) + "</g>",
    ] {
      let rendering = try await render(content)
      let actual = Self.quarters.map { rendering.pixel(x: $0.0, y: $0.1) }
      #expect(zip(actual, expected).allSatisfy(isClose), "\(orientation.rawValue): \(actual) \(expected)")
    }
  }

  @Test("image-orientation isn't a presentation attribute")
  func attribute() async throws {
    let data = try encodedImage(orientation: .down, type: .png)
    let expected = try expectedQuarters(of: data)
    let rendering = try await render(image(data, type: .png, #"image-orientation="none""#))
    let actual = Self.quarters.map { rendering.pixel(x: $0.0, y: $0.1) }
    #expect(zip(actual, expected).allSatisfy(isClose), "\(actual) \(expected)")
  }

  @Test("a bitmap turned by its orientation is placed by its turned size")
  func placed() async throws {
    // The image of 32 by 16 turned to 16 by 32, in a rectangle of 16 by 8.
    let data = try encodedImage(orientation: .right, type: .png)
    let url = "data:image/png;base64,\(data.base64EncodedString())"
    let meet = try await render(#"<image width="16" height="8" preserveAspectRatio="xMinYMin meet" href="\#(url)"/>"#)
    #expect(meet.pixel(x: 2, y: 4)[3] > 245, "\(meet.pixel(x: 2, y: 4))")
    #expect(meet.pixel(x: 10, y: 4)[3] < 10, "\(meet.pixel(x: 10, y: 4))")
    let slice = try await render(#"<image width="16" height="8" preserveAspectRatio="xMinYMin slice" href="\#(url)"/>"#)
    #expect(slice.pixel(x: 10, y: 4)[3] > 245, "\(slice.pixel(x: 10, y: 4))")
    #expect(slice.pixel(x: 10, y: 12)[3] < 10, "\(slice.pixel(x: 10, y: 12))")
  }

  @Test("a feImage draws its bitmap in the orientation of its metadata, whatever image-orientation is")
  func feImage() async throws {
    let data = try encodedImage(orientation: .left, type: .png)
    let expected = try expectedQuarters(of: data)
    let url = "data:image/png;base64,\(data.base64EncodedString())"
    for style in ["", #"style="image-orientation: none""#] {
      let content =
        #"<filter id="f" x="0" y="0" width="1" height="1" \#(style)>"#
        + #"<feImage href="\#(url)" preserveAspectRatio="none" \#(style)/></filter>"#
        + #"<rect width="16" height="16" filter="url(#f)"/>"#
      let rendering = try await render(content)
      let actual = Self.quarters.map { rendering.pixel(x: $0.0, y: $0.1) }
      #expect(zip(actual, expected).allSatisfy(isClose), "\(style): \(actual) \(expected)")
    }
  }
}
