import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a negative standard deviation of a blur is 0, which doesn't blur in its direction.
@MainActor
@Suite("Blur deviations")
struct BlurDeviationTests {
  /// A red square from 6 to 14 with a filter of the primitive, whose region is the document.
  private func square(_ primitive: String) -> String {
    #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">"# + primitive
      + #"</filter><rect x="6" y="6" width="8" height="8" fill="red" filter="url(#f)"/>"#
  }

  @Test(
    "a negative standard deviation blurs as 0 does, only in the directions whose deviation is positive",
    arguments: [("-1", "0"), ("-1 -1", "0 0"), ("2 -1", "2 0"), ("-1 2", "0 2")])
  func blur(deviation: String, zero: String) async throws {
    let negative = try await render(square(#"<feGaussianBlur stdDeviation=""# + deviation + #""/>"#))
    let expected = try await render(square(#"<feGaussianBlur stdDeviation=""# + zero + #""/>"#))
    #expect(negative.components == expected.components)
  }

  @Test("a blur that's negative in y blurs the edges across x only")
  func direction() async throws {
    let blurred = try await render(square(#"<feGaussianBlur stdDeviation="2 -1"/>"#))
    // Left of the square, the blur spreads the red.
    #expect(blurred.pixel(x: 5, y: 10)[3] > 0)
    // Above it, the square keeps its edge.
    #expect(blurred.pixel(x: 10, y: 5) == [0, 0, 0, 0])
    #expect(blurred.pixel(x: 10, y: 6)[3] > 0)
  }

  @Test(
    "a negative standard deviation of a drop shadow blurs the shadow as 0 does",
    arguments: [("-1", "0"), ("-1 -1", "0 0"), ("2 -1", "2 0"), ("-1 2", "0 2")])
  func dropShadow(deviation: String, zero: String) async throws {
    let negative = try await render(square(#"<feDropShadow dx="2" dy="2" stdDeviation=""# + deviation + #""/>"#))
    let expected = try await render(square(#"<feDropShadow dx="2" dy="2" stdDeviation=""# + zero + #""/>"#))
    #expect(negative.components == expected.components)
  }
}
