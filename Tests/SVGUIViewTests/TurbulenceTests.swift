import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feTurbulence` makes noise in its subregion.
@MainActor
@Suite("Turbulence")
struct TurbulenceTests {
  /// The red, green, blue and alpha components of the pixels of the rendered document, premultiplied, row by row
  /// from the top, in its user space of 20 by 20 at the scale of the snapshot.
  private func pixels(_ content: String) async throws -> (components: [UInt8], scale: Int) {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot().cgImage)
    var components = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try #require(
      CGContext(
        data: &components, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (components, image.width / 20)
  }

  /// The components of the pixel at a point of the user space.
  private func pixel(_ content: String, x: Int, y: Int) async throws -> [UInt8] {
    let (components, scale) = try await pixels(content)
    let offset = ((y * scale) * 20 * scale + x * scale) * 4
    return Array(components[offset..<(offset + 4)])
  }

  /// A rectangle that covers the document with a filter of the primitives, whose region is the document.
  private func filtered(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect width="20" height="20" filter="url(#f)"/>"#
  }

  @Test("turbulence of a frequency of 0 is transparent black")
  func zeroFrequency() async throws {
    let content = filtered(#"<feTurbulence/>"#)
    #expect(try await pixels(content).components.allSatisfy { $0 == 0 })
  }

  @Test("fractal noise of a frequency of 0 is gray, half transparent")
  func zeroFrequencyFractalNoise() async throws {
    let content = filtered(#"<feTurbulence type="fractalNoise" color-interpolation-filters="sRGB"/>"#)
    let components = try await pixel(content, x: 10, y: 10)
    for (component, expected) in zip(components, [64, 64, 64, 128]) {
      #expect(abs(Int(component) - expected) <= 1)
    }
  }

  @Test("noise with a negative frequency or number of octaves is transparent black")
  func errors() async throws {
    for attributes in [#"baseFrequency="0.1 -0.1""#, #"baseFrequency="0.1" numOctaves="-1""#] {
      let content = filtered(#"<feTurbulence type="fractalNoise" "# + attributes + "/>")
      #expect(try await pixels(content).components.allSatisfy { $0 == 0 })
    }
  }

  @Test("the seed is truncated towards 0, and the seeds of 0 and 1 are the same")
  func seed() async throws {
    func noise(_ seed: String) async throws -> [UInt8] {
      try await pixels(filtered(#"<feTurbulence baseFrequency="0.2" seed=""# + seed + #""/>"#)).components
    }
    let one = try await noise("1")
    #expect(one.contains { $0 != 0 })
    #expect(try await noise("1.5") == one)
    #expect(try await noise("0") == one)
    #expect(try await noise("-0.5") == one)
    #expect(try await noise("2") != one)
  }

  @Test("the noise is clipped to the subregion of the primitive")
  func subregion() async throws {
    let content = filtered(#"<feTurbulence type="fractalNoise" baseFrequency="0.2" width="10"/>"#)
    #expect(try await pixel(content, x: 5, y: 10)[3] != 0)
    #expect(try await pixel(content, x: 15, y: 10) == [0, 0, 0, 0])
  }
}
