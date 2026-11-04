import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that `feTurbulence` makes noise in its subregion.
@MainActor
@Suite("Turbulence")
struct TurbulenceTests {
  /// A rectangle that covers the document with a filter of the primitives, whose region is the document.
  private func filtered(_ primitives: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitives
      + #"</filter><rect width="20" height="20" filter="url(#f)"/>"#
  }

  @Test("turbulence of a frequency of 0 is transparent black")
  func zeroFrequency() async throws {
    let content = filtered(#"<feTurbulence/>"#)
    #expect(try await render(content).components.allSatisfy { $0 == 0 })
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
      #expect(try await render(content).components.allSatisfy { $0 == 0 })
    }
  }

  @Test("the seed is truncated towards 0, and the seeds of 0 and 1 are the same")
  func seed() async throws {
    func noise(_ seed: String) async throws -> [UInt8] {
      try await render(filtered(#"<feTurbulence baseFrequency="0.2" seed=""# + seed + #""/>"#)).components
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
