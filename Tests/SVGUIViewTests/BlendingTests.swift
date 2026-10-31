import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that elements blend with what's behind them in their isolation groups.
@MainActor
@Suite("Blending")
struct BlendingTests {
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

  /// A lime square with a yellow square over its right half, with the style.
  private func squares(_ style: String, around: (String, String) = ("", "")) -> String {
    #"<rect width="20" height="20" fill="lime"/>"# + around.0
      + #"<rect x="10" width="10" height="20" fill="yellow" style=""# + style + #""/>"# + around.1
  }

  @Test("multiply makes the product of the colors of an element and of what's behind it")
  func multiply() async throws {
    // Lime times yellow is lime.
    #expect(try await pixel(squares("mix-blend-mode: multiply"), x: 15, y: 10) == [0, 255, 0, 255])
    #expect(try await pixel(squares(""), x: 15, y: 10) == [255, 255, 0, 255])
  }

  @Test("an element blends only with what's in its isolation group")
  func isolation() async throws {
    let isolated = squares("mix-blend-mode: multiply", around: (#"<g style="isolation: isolate">"#, "</g>"))
    #expect(try await pixel(isolated, x: 15, y: 10) == [255, 255, 0, 255])
    let notIsolated = squares("mix-blend-mode: multiply", around: ("<g>", "</g>"))
    #expect(try await pixel(notIsolated, x: 15, y: 10) == [0, 255, 0, 255])
  }

  @Test("an element with an opacity blends that much")
  func opacity() async throws {
    let color = try await pixel(squares("mix-blend-mode: difference; opacity: 0.5"), x: 15, y: 10)
    // Lime minus yellow is red, which covers half of the lime.
    #expect(abs(Int(color[0]) - 128) <= 2 && abs(Int(color[1]) - 128) <= 2 && color[2] == 0, "\(color)")
  }
}
