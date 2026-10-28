import Foundation
import Testing

@testable import SVGCore

/// The red, green and blue from 0 to 255 and the alpha from 0 to 1 of a paint, or `nil` if it isn't a color.
private func rgba(of paint: Paint?) -> [Double]? {
  guard case .color(let color) = paint, let components = color.components else { return nil }
  return [components.red * 255, components.green * 255, components.blue * 255, components.alpha]
}

/// Whether two colors are the same, apart from rounding.
private func isClose(_ a: [Double]?, _ b: [Double]) -> Bool {
  guard let a, a.count == b.count else { return false }
  return zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
}

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

@Suite("Parsing colors")
struct ColorParsingTests {
  /// Colors, and their red, green and blue from 0 to 255 and their alpha.
  private static let colorValues: [(String, [Double])] = [
    ("rgb(0 128 0)", [0.0, 128, 0, 1]),
    ("rgb(0 128 0 / 50%)", [0, 128, 0, 0.5]),
    ("rgb(0, 128, 0, 0.5)", [0, 128, 0, 0.5]),
    ("rgba(0, 128, 0, 0.5)", [0, 128, 0, 0.5]),
    ("rgba(0 128 0)", [0, 128, 0, 1]),
    ("RGB(0, 128, 0)", [0, 128, 0, 1]),
    ("rgb(0%, 50%, 100%)", [0, 127.5, 255, 1]),
    ("rgb(300, -5, 0, 2)", [255, 0, 0, 1]),
    ("rgb(none 128 0 / none)", [0, 128, 0, 0]),
  ]

  @Test("colors in the legacy and the modern syntax of CSS Color, with their values clamped", arguments: colorValues)
  func colors(text: String, expected: [Double]) {
    #expect(isClose(rgba(of: Paint(text)), expected), "\(text): \(String(describing: rgba(of: Paint(text))))")
  }

  @Test(
    "invalid colors",
    arguments: [
      "rgb(0 128 0, 0.5)", "rgb(0, 128 0)", "rgb(0, 128, none)", "rgb(0 128 0 / 0.5 0.5)", "rgb(0, 128, 0",
    ])
  func invalidColors(text: String) {
    #expect(Paint(text) == nil)
    #expect(ColorValue(text) == nil)
  }

  @Test("stop-color and flood-color read the same colors")
  func otherProperties() throws {
    let green = try #require(SVGAttributeScanner.parseColor(description: "rgb(0 128 0 / 0.5)"))
    #expect(ColorValue("RGBA(0, 128, 0, 50%)") == .color(green))
  }
}
