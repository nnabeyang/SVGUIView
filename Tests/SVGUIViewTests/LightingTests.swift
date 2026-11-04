import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feDiffuseLighting` and `feSpecularLighting` light the surface of the alpha of their input.
@MainActor
@Suite("Lighting")
struct LightingTests {
  /// The rendered document of the user space of 20 by 20, whose pixels are indexed from the top left.
  private struct Rendering {
    let components: [UInt8]
    let width: Int
    /// The pixels in a unit of the user space.
    let scale: Int

    /// The red, green, blue and alpha components of a pixel, premultiplied.
    func pixel(_ column: Int, _ row: Int) -> [UInt8] {
      let offset = (row * width + column) * 4
      return Array(components[offset..<(offset + 4)])
    }
  }

  private func render(_ content: String) async throws -> Rendering {
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
    return Rendering(components: components, width: image.width, scale: image.width / 20)
  }

  /// An opaque rectangle that covers the document, with a filter of the primitive in sRGB whose region is from 6 to
  /// 14, so that the surface is flat.
  private func flat(_ primitive: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="6" y="6" width="8" height="8" color-interpolation-filters="sRGB">"#
      + primitive + #"</filter><rect width="20" height="20" filter="url(#f)"/>"#
  }

  /// A square from 6 to 14 on a transparent surface, with a filter of the primitive whose region is the document.
  private func square(_ primitive: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitive
      + #"</filter><rect x="6" y="6" width="8" height="8" filter="url(#f)"/>"#
  }

  @Test("a flat surface lit from above reflects the lighting color, opaque")
  func diffuseFromAbove() async throws {
    let rendering = try await render(
      flat(#"<feDiffuseLighting lighting-color="lime"><feDistantLight elevation="90"/></feDiffuseLighting>"#))
    #expect(rendering.pixel(10 * rendering.scale, 10 * rendering.scale) == [0, 255, 0, 255])
  }

  @Test("a flat surface lit from its side is black, opaque")
  func diffuseFromSide() async throws {
    let rendering = try await render(
      flat(#"<feDiffuseLighting lighting-color="lime"><feDistantLight elevation="0"/></feDiffuseLighting>"#))
    #expect(rendering.pixel(10 * rendering.scale, 10 * rendering.scale) == [0, 0, 0, 255])
  }

  @Test("the specular reflection has the greatest of its colors as its alpha")
  func specular() async throws {
    let rendering = try await render(
      flat(
        #"<feSpecularLighting lighting-color="rgb(0 128 0)"><feDistantLight elevation="90"/></feSpecularLighting>"#))
    #expect(rendering.pixel(10 * rendering.scale, 10 * rendering.scale) == [0, 128, 0, 128])
  }

  @Test(
    "a missing light source and negative constants are transparent black",
    arguments: [
      #"<feDiffuseLighting/>"#,
      #"<feDiffuseLighting diffuseConstant="-1"><feDistantLight elevation="90"/></feDiffuseLighting>"#,
      #"<feSpecularLighting specularConstant="-1"><feDistantLight elevation="90"/></feSpecularLighting>"#,
    ])
  func errors(_ primitive: String) async throws {
    let rendering = try await render(flat(primitive))
    #expect(rendering.components.allSatisfy { $0 == 0 })
  }

  @Test("an azimuth of 0 lights the edges that face the x-axis, and one of 90 those that face down")
  func azimuth() async throws {
    let fromRight = try await render(
      square(#"<feDiffuseLighting surfaceScale="5"><feDistantLight azimuth="0" elevation="45"/></feDiffuseLighting>"#))
    let s = fromRight.scale
    #expect(fromRight.pixel(14 * s - 1, 10 * s)[0] > fromRight.pixel(6 * s, 10 * s)[0] + 64)
    let fromBelow = try await render(
      square(#"<feDiffuseLighting surfaceScale="5"><feDistantLight azimuth="90" elevation="45"/></feDiffuseLighting>"#))
    #expect(fromBelow.pixel(10 * s, 14 * s - 1)[0] > fromBelow.pixel(10 * s, 6 * s)[0] + 64)
  }
}
