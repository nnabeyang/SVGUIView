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

  /// Colors in the color spaces of CSS Color 4, and their red, green and blue from 0 to 255, rounded, and their
  /// alpha.
  private static let colorSpaceValues: [(String, [Double])] = [
    // The examples of CSS Color 4 of the same color, #7d2329.
    ("lab(29.2345% 39.3825 20.0664)", [125, 35, 41, 1]),
    ("lch(29.2345% 44.2 27)", [125, 35, 41, 1]),
    ("oklab(40.101% 0.1147 0.0453)", [125, 35, 41, 1]),
    ("oklch(40.101% 0.12332 21.555)", [125, 35, 41, 1]),
    ("LCH(29.2345% 44.2 0.075turn)", [125, 35, 41, 1]),
    ("lab(50% 0 0)", [119, 119, 119, 1]),
    ("lab(50 0 0 / 0.5)", [119, 119, 119, 0.5]),
    ("lab(100% 0 0)", [255, 255, 255, 1]),
    ("lab(150 0 0)", [255, 255, 255, 1]),
    ("lab(none 0 0)", [0, 0, 0, 1]),
    ("lch(50% -10 30)", [119, 119, 119, 1]),
    ("oklab(1 0 0)", [255, 255, 255, 1]),
    ("oklab(100% 0% 0% / 50%)", [255, 255, 255, 0.5]),
    ("oklch(0 0 none)", [0, 0, 0, 1]),
    ("color(srgb 0.5 0 1)", [128, 0, 255, 1]),
    ("color(srgb 50% 0% 100% / 0.25)", [128, 0, 255, 0.25]),
    ("color(srgb-linear 0.2 0 1)", [124, 0, 255, 1]),
    ("color(xyz-d65 0.95047 1 1.08883)", [255, 255, 255, 1]),
    ("color(xyz 0.95047 1 1.08883)", [255, 255, 255, 1]),
    ("color(xyz-d50 0.96422 1 0.82521)", [255, 255, 255, 1]),
    ("color(display-p3 1 1 1)", [255, 255, 255, 1]),
    ("color(a98-rgb 1 1 1)", [255, 255, 255, 1]),
    ("color(prophoto-rgb 1 1 1)", [255, 255, 255, 1]),
    ("color(rec2020 1 1 1)", [255, 255, 255, 1]),
    ("color(rec2020 0 0 0)", [0, 0, 0, 1]),
    // The red of Display P3 is outside sRGB, and its channels are clamped.
    ("color(display-p3 1 0 0)", [255, 0, 0, 1]),
  ]

  @Test("colors in the color spaces of CSS Color 4 are converted to sRGB, and clamped to it", arguments: colorSpaceValues)
  func colorSpaces(text: String, expected: [Double]) {
    let rgba = rgba(of: Paint(text)).map { [$0[0].rounded(), $0[1].rounded(), $0[2].rounded(), $0[3]] }
    #expect(isClose(rgba, expected), "\(text): \(String(describing: rgba))")
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
      "#aaz", "#aa", "#12345", "rgba(0, 50%, 0, 0.5)", "rgb(0, 50%, 0)",
      "lab(50, 0, 0)", "lab(50% 0)", "lab(50% 0 0deg)", "lch(50% 0 0 0)", "oklch(50% 0.1)", "color(foo 1 0 0)",
      "color(srgb 1, 0, 0)", "color(display-p3)", "color(1 0 0)", "color(srgb 1 0 0",
    ])
  func invalidColors(text: String) {
    #expect(Paint(text) == nil)
    #expect(ColorValue(text) == nil)
  }

  @Test("hex colors have 3, 4, 6 or 8 digits and nothing after them, and the modern rgb() mixes numbers and percentages")
  func hexColorsAndMixedValues() {
    for text in ["#abc", "#abcd", "#aabbcc", "#aabbccdd", "rgb(0 50% 0)"] {
      #expect(Paint(text) != nil, "\(text)")
    }
    #expect(Paint("#aaaaz") == nil)
  }

  @Test("a function that isn't supported isn't a color, and paints black as a name that isn't a color does")
  func unsupportedFunctions() {
    #expect(ColorValue("color-mix(in srgb, red, blue)") == nil)
    #expect(Paint("color-mix(in srgb, red, blue)") == Paint("black"))
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

  @Test("a paint server reference takes a fallback of none, a color or currentColor, and nothing else after it")
  func paintServerFallbacks() {
    #expect(Paint("url(#a)") == .url("a", fallback: nil))
    #expect(Paint("url(#a) green") == .url("a", fallback: Paint("green")))
    #expect(Paint("url(#a) #0f0") == .url("a", fallback: Paint("#0f0")))
    #expect(Paint("url(#a)  none ") == .url("a", fallback: Paint.none))
    #expect(Paint("url(#a) currentColor") == .url("a", fallback: .currentColor))
    // SVG 2 has no ICC colors, so a value with one is invalid.
    for text in [
      "url(#a) url(#b)", "url(#a) foo", "url(#a) green blue", "url(#a) green icc-color(acmecmyk, 0.11, 0.48)",
    ] {
      #expect(Paint(text) == nil, "\(text)")
    }
    #expect(
      ComputedStyle.initial.resolved(.url("a", fallback: .currentColor))
        == .url("a", fallback: .color(ComputedStyle.initial.color)))
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

  @Test("stop-color, flood-color and style sheets read the colors of the color spaces of CSS Color 4")
  func otherPropertiesInColorSpaces() throws {
    guard case .color(let white) = ColorValue("oklab(1 0 0)"), let components = white.components else {
      Issue.record("oklab() isn't a color value")
      return
    }
    #expect(isClose([components.red, components.green, components.blue].map { ($0 * 255).rounded() }, [255, 255, 255]))
    let base = parse(
      "<style>rect { fill: color(srgb 0 0.5 0) }</style>"
        + #"<rect id="a" width="10" height="10"/><stop id="s" stop-color="lab(100 0 0)"/>"#)
    let elements = base.root?.elements ?? []
    let rect = try #require(elements.first { $0.base.id == "a" })
    #expect(isClose(rgba(of: rect.style.fill), [0, 127.5, 0, 1]))
    let stop = try #require(elements.first { $0.base.id == "s" })
    guard case .color(let color) = stop.style.stopColor, let components = color.components else {
      Issue.record("The stop color isn't a color")
      return
    }
    #expect(isClose([components.red * 255, components.green * 255, components.blue * 255].map { $0.rounded() }, [255, 255, 255]))
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
