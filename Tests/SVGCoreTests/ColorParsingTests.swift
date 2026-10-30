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
    ("hsl(0, 70%, 50%)", [216.75, 38.25, 38.25, 1]),
    ("hsl(120, 100%, 25%)", [0, 127.5, 0, 1]),
    ("hsl(999, 100%, 25%)", [82.875, 0, 127.5, 1]),
    ("hsl(-240, 100%, 25%)", [0, 127.5, 0, 1]),
    ("hsl(120, 200%, 25%)", [0, 191.25, 0, 1]),
    ("hsl(120, -50%, 25%)", [63.75, 63.75, 63.75, 1]),
    ("hsla(120, 100%, 25%, 0.5)", [0, 127.5, 0, 0.5]),
    ("hsl(120, 100%, 25%, 0.5)", [0, 127.5, 0, 0.5]),
    ("hsl(120 100% 25% / 50%)", [0, 127.5, 0, 0.5]),
    ("hsl(120deg 100 25)", [0, 127.5, 0, 1]),
    ("HSL(0.5turn 100% 50%)", [0, 255, 255, 1]),
    ("hsl(200grad 100% 50%)", [0, 255, 255, 1]),
    ("hsl(3.14159265rad 100% 50%)", [0, 255, 255, 1]),
    ("hsl(none 0% 50%)", [127.5, 127.5, 127.5, 1]),
    ("hwb(120 0% 50%)", [0, 127.5, 0, 1]),
    ("hwb(0 60% 60% / 0.5)", [127.5, 127.5, 127.5, 0.5]),
  ]

  @Test("colors in the legacy and the modern syntax of CSS Color, with their values clamped", arguments: colorValues)
  func colors(text: String, expected: [Double]) {
    #expect(isClose(rgba(of: Paint(text)), expected), "\(text): \(String(describing: rgba(of: Paint(text))))")
  }

  @Test("hsl() is the color of the same hex in 8 bits")
  func hslAsHex() {
    #expect(rgba(of: Paint("hsl(0, 70%, 50%)"))?.map { $0.rounded() } == rgba(of: Paint("#d92626")))
  }

  @Test(
    "invalid colors",
    arguments: [
      "hsl(120, 100, 25%)", "hsl(120 100% 25%, 0.5)", "rgb(0 128 0, 0.5)", "rgb(0, 128 0)", "rgb(0, 128, none)",
      "hwb(120, 0%, 50%)", "hsl(120, 100%, 25%", "hsl(120px 100% 50%)", "hsl(120 100% 50% / 0.5 0.5)",
    ])
  func invalidColors(text: String) {
    #expect(Paint(text) == nil)
    #expect(ColorValue(text) == nil)
  }

  @Test("a function that isn't supported isn't a color, and paints black as a name that isn't a color does")
  func unsupportedFunctions() {
    #expect(ColorValue("lab(50 0 0)") == nil)
    #expect(Paint("lab(50 0 0)") == Paint("black"))
  }

  /// The named colors of CSS Color 4.
  private static let cssColorNames: Set<String> = [
    "aliceblue", "antiquewhite", "aqua", "aquamarine", "azure", "beige", "bisque", "black",
    "blanchedalmond", "blue", "blueviolet", "brown", "burlywood", "cadetblue", "chartreuse", "chocolate",
    "coral", "cornflowerblue", "cornsilk", "crimson", "cyan", "darkblue", "darkcyan", "darkgoldenrod",
    "darkgray", "darkgreen", "darkgrey", "darkkhaki", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid",
    "darkred", "darksalmon", "darkseagreen", "darkslateblue", "darkslategray", "darkslategrey", "darkturquoise", "darkviolet",
    "deeppink", "deepskyblue", "dimgray", "dimgrey", "dodgerblue", "firebrick", "floralwhite", "forestgreen",
    "fuchsia", "gainsboro", "ghostwhite", "gold", "goldenrod", "gray", "green", "greenyellow",
    "grey", "honeydew", "hotpink", "indianred", "indigo", "ivory", "khaki", "lavender",
    "lavenderblush", "lawngreen", "lemonchiffon", "lightblue", "lightcoral", "lightcyan", "lightgoldenrodyellow", "lightgray",
    "lightgreen", "lightgrey", "lightpink", "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray", "lightslategrey",
    "lightsteelblue", "lightyellow", "lime", "limegreen", "linen", "magenta", "maroon", "mediumaquamarine",
    "mediumblue", "mediumorchid", "mediumpurple", "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise", "mediumvioletred",
    "midnightblue", "mintcream", "mistyrose", "moccasin", "navajowhite", "navy", "oldlace", "olive",
    "olivedrab", "orange", "orangered", "orchid", "palegoldenrod", "palegreen", "paleturquoise", "palevioletred",
    "papayawhip", "peachpuff", "peru", "pink", "plum", "powderblue", "purple", "rebeccapurple",
    "red", "rosybrown", "royalblue", "saddlebrown", "salmon", "sandybrown", "seagreen", "seashell",
    "sienna", "silver", "skyblue", "slateblue", "slategray", "slategrey", "snow", "springgreen",
    "steelblue", "tan", "teal", "thistle", "tomato", "turquoise", "violet", "wheat",
    "white", "whitesmoke", "yellow", "yellowgreen",
  ]

  @Test("the named colors are the ones of CSS Color and transparent, and other names aren't colors")
  func namedColors() {
    #expect(SVGColorName.names == Self.cssColorNames.union(["transparent"]))
    #expect(isClose(rgba(of: Paint("MediumVioletRed")), [199, 21, 133, 1]))
    #expect(rgba(of: Paint("violetred")) == nil)
    #expect(rgba(of: Paint("transparent")) == [0, 0, 0, 0])
  }

  @Test("stop-color, flood-color and style sheets read the same colors")
  func otherProperties() throws {
    let green = try #require(SVGAttributeScanner.parseColor(description: "rgb(0 127.5 0 / 0.5)"))
    #expect(ColorValue("HSLA(120, 100%, 25%, 0.5)") == .color(green))
    let base = parse(
      "<style>rect { fill: hwb(120 0% 50%) }</style>"
        + #"<rect id="a" width="10" height="10"/><stop id="s" stop-color="hsl(120 100% 25%)"/>"#)
    let elements = base.root?.elements ?? []
    let rect = try #require(elements.first { $0.base.id == "a" })
    #expect(isClose(rgba(of: rect.style.fill), [0, 127.5, 0, 1]))
    let stop = try #require(elements.first { $0.base.id == "s" })
    #expect(stop.style.stopColor == .color(SVGAttributeScanner.parseColor(description: "rgb(0, 127.5, 0)")!))
  }

  @Test("CSS animations interpolate hsl() colors as other colors")
  func interpolation() {
    let base = parse(
      "<style>@keyframes k { from { fill: hsl(0, 100%, 50%) } to { fill: rgb(0, 0, 255) } } "
        + "rect { animation: k 1s linear }</style>" + #"<rect id="a" width="10" height="10"/>"#)
    let fill = base.at(time: 0.5).root?.elements.first { $0.base.id == "a" }?.style.fill
    #expect(isClose(rgba(of: fill), [127.5, 0, 127.5, 1]))
  }
}
