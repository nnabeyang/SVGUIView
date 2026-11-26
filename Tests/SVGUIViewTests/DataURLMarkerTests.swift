import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a marker can be an element of the SVG document of a data URL.
@MainActor
@Suite("Markers of data URLs")
struct DataURLMarkerTests {
  private let green: [UInt8] = [0, 128, 0, 255]
  private let transparent: [UInt8] = [0, 0, 0, 0]

  /// A data URL of an SVG document whose marker `m` is a green square of 2 by 2 about the vertex, with the content
  /// before it.
  private func document(_ content: String = "") -> String {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg">"# + content
      + #"<marker id="m" markerUnits="userSpaceOnUse" markerWidth="2" markerHeight="2" refX="1" refY="1">"#
      + #"<rect width="2" height="2" fill="green"/></marker></svg>"#
    return "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
  }

  /// A path through 3 vertices, with the markers of the attributes.
  private func path(_ markers: String) -> String {
    #"<path d="M5 5 H10 H15" fill="none" "# + markers + "/>"
  }

  @Test("a marker of a data URL is drawn at the start, the middle and the end vertices")
  func vertices() async throws {
    let url = document()
    let rendering = try await render(
      path(#"marker-start="url(\#(url)#m)" marker-mid="url(\#(url)#m)" marker-end="url(\#(url)#m)""#))
    for x in [5, 10, 15] {
      #expect(rendering.pixel(x: x, y: 5) == green, "\(x)")
    }
    #expect(rendering.pixel(x: 7, y: 5) == transparent)
  }

  @Test(
    "a data URL in quotes, and in a declaration of a style sheet, names the marker too",
    arguments: [#"marker-start="url('URL#m')""#, #"style="marker-start: url('URL#m')""#, #"style="marker: url(URL#m)""#])
  func quotesAndStyles(_ markers: String) async throws {
    let content = path(markers.replacingOccurrences(of: "URL", with: document()))
    #expect(try await pixel(content, x: 5, y: 5) == green)
  }

  @Test(
    "a data URL without a fragment, with an ID that the document doesn't have, or that isn't SVG draws no marker",
    arguments: ["URL", "URL#n", "data:text/plain,abc#m", "data:image/svg+xml;base64,%%%#m"])
  func noMarker(_ reference: String) async throws {
    let url = reference.replacingOccurrences(of: "URL", with: document())
    #expect(try await pixel(path(#"marker-start="url(\#(url))""#), x: 5, y: 5) == transparent)
  }

  @Test("a marker of a data URL can have the markers of another data URL in its content")
  func nested() async throws {
    // The content of the outer marker is a path with the marker of the inner document at its start, beside the square.
    let inner = document()
    let outerSVG =
      #"<svg xmlns="http://www.w3.org/2000/svg"><marker id="m" markerUnits="userSpaceOnUse" markerWidth="10" "#
      + #"markerHeight="10" refX="0" refY="0" overflow="visible"><path d="M3 0 H4" fill="none" "#
      + #"marker-start="url(\#(inner)#m)"/></marker></svg>"#
    let outer = "data:image/svg+xml;base64," + Data(outerSVG.utf8).base64EncodedString()
    let rendering = try await render(#"<path d="M5 5 H15" fill="none" marker-start="url(\#(outer)#m)"/>"#)
    #expect(rendering.pixel(x: 8, y: 5) == green)
  }

  @Test("the computed value of a marker of a data URL is the URL in quotes")
  func computedValue() throws {
    let url = document()
    let view = SVGUIView(
      data: Data(
        (#"<svg xmlns="http://www.w3.org/2000/svg"><path id="p" d="M0 0 H1" marker-start="url("#
          + url + #"#m)"/></svg>"#).utf8))
    let style = try #require(view.document.element(id: "p")).computedStyle
    #expect(style.property("marker-start") == #"url(""# + url + #"#m")"#)
  }
}
