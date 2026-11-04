import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the primitives of a filter take the inputs that they name.
@MainActor
@Suite("Filter inputs")
struct FilterInputTests {
  /// The red, green, blue and alpha components of a pixel of the rendered document, premultiplied, in its user space
  /// of 20 by 20.
  private func pixel(_ content: String, x: Int, y: Int) async throws -> [UInt8] {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot().cgImage)
    let scale = image.width / 20
    var components = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image,
      in: CGRect(x: -x * scale, y: y * scale - image.height + 1, width: image.width, height: image.height))
    return components
  }

  /// A red square from 2 to 8 with a filter of the primitives, whose region is the document.
  private func square(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect x="2" y="2" width="6" height="6" fill="red" filter="url(#f)"/>"#
  }

  private let red: [UInt8] = [255, 0, 0, 255]
  private let transparent: [UInt8] = [0, 0, 0, 0]

  @Test("SourceAlpha has the alpha of the source and colors of 0")
  func sourceAlpha() async throws {
    let content = square(#"<feOffset in="SourceAlpha"/>"#)
    #expect(try await pixel(content, x: 5, y: 5) == [0, 0, 0, 255])
    #expect(try await pixel(content, x: 12, y: 12) == transparent)
  }

  @Test("SourceGraphic after SourceAlpha in the same primitive keeps its colors")
  func sourceGraphicAfterSourceAlpha() async throws {
    // The arithmetic of k3 alone is the second input.
    let content = square(#"<feComposite in="SourceAlpha" in2="SourceGraphic" operator="arithmetic" k3="1"/>"#)
    #expect(try await pixel(content, x: 5, y: 5) == red)
  }

  @Test(
    "a negative standard deviation gives the input that the blur names, not the result before it",
    arguments: ["2 -1", "-1"])
  func negativeDeviation(_ deviation: String) async throws {
    let content = square(
      #"<feOffset dx="10"/><feGaussianBlur in="SourceGraphic" stdDeviation=""# + deviation + #""/>"#)
    #expect(try await pixel(content, x: 5, y: 5) == red)
    #expect(try await pixel(content, x: 15, y: 5) == transparent)
  }
}
