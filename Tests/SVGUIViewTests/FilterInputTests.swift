import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the primitives of a filter take the inputs that they name.
@MainActor
@Suite("Filter inputs")
struct FilterInputTests {
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
