import Foundation
import Testing

@testable import SVGCore

/// The red, green and blue from 0 to 255 and the alpha from 0 to 1 of a paint, or `nil` if it isn't a color. A
/// color with missing components has them as 0, as where it isn't interpolated.
private func rgba(of paint: Paint?) -> [Double]? {
  let color: SVGColor
  switch paint {
  case .color(let value)?: color = value
  case .expression(let expression)?: color = expression.resolved(currentColor: .named(SVGColorName(name: "black")))
  default: return nil
  }
  guard let components = color.components else { return nil }
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
  ]

  @Test("colors in the color spaces of CSS Color 4 are converted to sRGB", arguments: colorSpaceValues)
  func colorSpaces(text: String, expected: [Double]) {
    let rgba = rgba(of: Paint(text)).map { [$0[0].rounded(), $0[1].rounded(), $0[2].rounded(), $0[3]] }
    #expect(isClose(rgba, expected), "\(text): \(String(describing: rgba))")
  }

  /// Colors outside sRGB, and their red, green and blue of extended sRGB, from 0 to 255 in sRGB, and their alpha.
  private static let wideValues: [(String, [Double])] = [
    ("color(display-p3 1 0 0)", [278.732, -57.819, -38.284, 1]),
    ("color(display-p3 100% 0% 0% / 0.5)", [278.732, -57.819, -38.284, 0.5]),
    ("color(rec2020 0 1 0)", [-201.546, 269.357, -89.292, 1]),
    ("color-mix(in srgb, color(display-p3 1 0 0), white)", [266.866, 98.591, 108.358, 1]),
    ("rgb(from color(display-p3 1 0 0) r g b)", [278.732, -57.819, -38.284, 1]),
  ]

  @Test("colors outside sRGB keep their components outside 0 to 1", arguments: wideValues)
  func wideColors(text: String, expected: [Double]) throws {
    let rgba = try #require(rgba(of: Paint(text)))
    #expect(zip(rgba, expected).allSatisfy { abs($0 - $1) < 0.05 }, "\(text): \(rgba)")
    if case .color(let color) = Paint(text) { #expect(color.isOutsideSRGB) }
  }

  @Test(
    "colors in sRGB, and colors of sRGB functions, which are clamped to it, aren't outside sRGB",
    arguments: [
      "red", "#fff", "rgb(300 -5 0)", "hsl(120 200% 25%)", "hwb(0 -10% 0%)", "lab(100 0 0)", "oklch(1 0 0)",
      "color(display-p3 1 1 1)", "color(rec2020 1 1 1)", "color(xyz 0.95047 1 1.08883)",
    ])
  func colorsInSRGB(text: String) throws {
    guard case .color(let color) = Paint(text) else {
      Issue.record("\(text) isn't a color")
      return
    }
    #expect(!color.isOutsideSRGB)
    let c = try #require(color.components)
    #expect([c.red, c.green, c.blue].allSatisfy { (0...1).contains($0) }, "\(text): \(c)")
  }

  /// Mixes of `color-mix()`, and their red, green and blue from 0 to 255, rounded, and their alpha.
  private static let mixValues: [(String, [Double])] = [
    ("color-mix(in srgb, red, blue)", [128, 0, 128, 1]),
    ("color-mix(in srgb, red 25%, blue)", [64, 0, 191, 1]),
    ("color-mix(in srgb, 25% red, blue)", [64, 0, 191, 1]),
    ("color-mix(in srgb, red, blue 75%)", [64, 0, 191, 1]),
    ("color-mix(in srgb, red 60%, blue 60%)", [128, 0, 128, 1]),
    // Percentages that add up to less than 100% lower the alpha.
    ("color-mix(in srgb, red 30%, blue 30%)", [128, 0, 128, 0.6]),
    ("color-mix(in srgb-linear, red, blue)", [188, 0, 188, 1]),
    ("color-mix(in oklab, white, black)", [99, 99, 99, 1]),
    // White and black have no hue in oklch.
    ("color-mix(in oklch, white, black)", [99, 99, 99, 1]),
    ("color-mix(in hsl, red, blue)", [255, 0, 255, 1]),
    ("color-mix(in hsl shorter hue, red, blue)", [255, 0, 255, 1]),
    ("color-mix(in hsl longer hue, red, blue)", [0, 255, 0, 1]),
    ("color-mix(in hsl increasing hue, red, blue)", [0, 255, 0, 1]),
    ("color-mix(in hsl decreasing hue, red, blue)", [255, 0, 255, 1]),
    // White takes the hue of red.
    ("color-mix(in hsl, red, white)", [223, 159, 159, 1]),
    ("color-mix(in srgb, color-mix(in srgb, red, blue), white)", [191, 128, 191, 1]),
    // The components are mixed with the alpha premultiplied.
    ("color-mix(in srgb, rgb(255 0 0 / 0), blue)", [0, 0, 255, 0.5]),
    ("COLOR-MIX(IN SRGB, red, blue)", [128, 0, 128, 1]),
  ]

  @Test("color-mix() mixes colors in a color space, as CSS Color 5 computes it", arguments: mixValues)
  func colorMix(text: String, expected: [Double]) {
    let rgba = rgba(of: Paint(text)).map { [$0[0].rounded(), $0[1].rounded(), $0[2].rounded(), $0[3]] }
    #expect(isClose(rgba, expected), "\(text): \(String(describing: rgba))")
  }

  @Test(
    "invalid mixes",
    arguments: [
      "color-mix(in srgb, red 0%, blue 0%)", "color-mix(in srgb, red -10%, blue)", "color-mix(in srgb, red 150%, blue)",
      "color-mix(srgb, red, blue)", "color-mix(in foo, red, blue)", "color-mix(in srgb longer hue, red, blue)",
      "color-mix(in srgb, red, foo)", "color-mix(in srgb, red 50, blue)", "color-mix(in srgb, red)",
      "color-mix(in hsl longer, red, blue)",
    ])
  func invalidMixes(text: String) {
    #expect(ColorValue(text) == nil)
    #expect(Paint(text) == nil)
  }

  /// Relative colors, and their red, green and blue from 0 to 255, rounded, and their alpha.
  private static let relativeValues: [(String, [Double])] = [
    ("rgb(from red r g 255)", [255, 0, 255, 1]),
    ("rgb(from #0000ff b g r)", [255, 0, 0, 1]),
    ("RGB(FROM red R G B / 50%)", [255, 0, 0, 0.5]),
    // The alpha is the alpha of the origin where it's omitted.
    ("rgb(from rgb(255 0 0 / 0.5) r g b)", [255, 0, 0, 0.5]),
    ("rgba(from red r g b / alpha)", [255, 0, 0, 1]),
    ("rgb(from red none g b)", [0, 0, 0, 1]),
    ("hsl(from red h s 25%)", [128, 0, 0, 1]),
    ("hsl(from red 120deg s l)", [0, 255, 0, 1]),
    ("hwb(from red h 50 b)", [255, 128, 128, 1]),
    ("lab(from white l 0 0)", [255, 255, 255, 1]),
    ("oklab(from black l a b / 0.25)", [0, 0, 0, 0.25]),
    ("lch(from blue l c h)", [0, 0, 255, 1]),
    ("oklch(from red l c h / 50%)", [255, 0, 0, 0.5]),
    ("color(from red srgb r g b)", [255, 0, 0, 1]),
    ("color(from red srgb-linear r g b)", [255, 0, 0, 1]),
    ("color(from red xyz x y z)", [255, 0, 0, 1]),
    ("color(from blue display-p3 r g b)", [0, 0, 255, 1]),
    ("rgb(from color-mix(in srgb, red, blue) r 0 b)", [128, 0, 128, 1]),
  ]

  @Test("relative colors take the components of their origins by their names", arguments: relativeValues)
  func relativeColors(text: String, expected: [Double]) {
    let rgba = rgba(of: Paint(text)).map { [$0[0].rounded(), $0[1].rounded(), $0[2].rounded(), $0[3]] }
    #expect(isClose(rgba, expected), "\(text): \(String(describing: rgba))")
  }

  @Test(
    "invalid relative colors",
    arguments: [
      "rgb(from red r g)", "rgb(from red r g c)", "rgb(from red, r, g, b)", "rgb(from foo r g b)",
      "color(from red foo r g b)", "color(from red xyz r g b)", "oklch(from red l c calc(h + 180))",
      "hsl(from red h s)", "rgb(from red r g b /)",
    ])
  func invalidRelativeColors(text: String) {
    #expect(ColorValue(text) == nil)
    #expect(Paint(text) == nil)
  }

  @Test("a relative color of currentcolor is resolved where it's used, with the color of the element that uses it")
  func relativeCurrentColor() throws {
    let base = parse(
      #"<g color="red" fill="rgb(from currentcolor r g 255)"><rect id="a" width="10" height="10"/>"#
        + #"<rect id="b" color="lime" width="10" height="10"/></g>"#)
    let elements = base.root?.elements ?? []
    func fill(_ id: String) throws -> [Double]? {
      let element = try #require(elements.first { $0.base.id == id })
      return rgba(of: element.style.resolved(element.style.fill)).map { $0.map { $0.rounded() } }
    }
    #expect(try fill("a") == [255, 0, 255, 1])
    #expect(try fill("b") == [0, 255, 255, 1])
  }

  @Test("a mix of currentcolor is resolved where it's used, with the color of the element that uses it")
  func mixOfCurrentColor() throws {
    #expect(ColorValue("color-mix(in srgb, currentcolor, white)") != nil)
    let base = parse(
      #"<g id="g" color="blue" fill="color-mix(in srgb, currentcolor, white)"><rect id="a" width="10" height="10"/>"#
        + #"<rect id="b" color="red" width="10" height="10"/>"#
        + #"<rect id="c" color="color-mix(in srgb, currentcolor, white)" width="10" height="10"/></g>"#)
    let elements = base.root?.elements ?? []
    func fill(_ id: String) throws -> [Double]? {
      let element = try #require(elements.first { $0.base.id == id })
      return rgba(of: element.style.resolved(element.style.fill)).map { $0.map { $0.rounded() } }
    }
    // The child that inherits the mix mixes its own color.
    #expect(try fill("a") == [128, 128, 255, 1])
    #expect(try fill("b") == [255, 128, 128, 1])
    // currentcolor in color is the color of the parent.
    let c = try #require(elements.first { $0.base.id == "c" })
    #expect(rgba(of: .color(c.style.color)).map { $0.map { $0.rounded() } } == [128, 128, 255, 1])
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
    #expect(ColorValue("light-dark(red, blue)") == nil)
    #expect(Paint("light-dark(red, blue)") == Paint("black"))
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

  /// Mixes of colors with missing components, which take the components of the other color, and their red, green
  /// and blue from 0 to 255, rounded, and their alpha.
  private static let missingMixValues: [(String, [Double])] = [
    ("color-mix(in srgb, rgb(none 0 0), red)", [255, 0, 0, 1]),
    ("color-mix(in srgb, red, rgb(none 0 0))", [255, 0, 0, 1]),
    // Both colors miss the red, which is 0.
    ("color-mix(in srgb, rgb(none 0 0), rgb(none 255 0))", [0, 128, 0, 1]),
    // A missing alpha takes the alpha of the other color.
    ("color-mix(in srgb, rgb(0 0 255 / none), rgb(255 0 0 / 0.5))", [128, 0, 128, 0.5]),
    // The x of XYZ is analogous to the red of sRGB, and is carried forward to it.
    ("color-mix(in srgb, color(xyz none 0 0), red)", [255, 0, 0, 1]),
    // The hue of HSL isn't analogous to any component of sRGB, and is 0, which is red.
    ("color-mix(in srgb, hsl(none 100% 50%), blue)", [128, 0, 128, 1]),
    // A relative color with `none` misses that component too.
    ("color-mix(in srgb, rgb(from blue none g b), red)", [255, 0, 128, 1]),
  ]

  @Test("color-mix() takes a missing component from the other color", arguments: missingMixValues)
  func missingMix(text: String, expected: [Double]) {
    let rgba = rgba(of: Paint(text)).map { [$0[0].rounded(), $0[1].rounded(), $0[2].rounded(), $0[3]] }
    #expect(isClose(rgba, expected), "\(text): \(String(describing: rgba))")
  }

  @Test("a missing hue is carried forward to the hue of another polar space, and takes the hue of the other color")
  func missingHue() throws {
    func hue(_ text: String) throws -> Double {
      let rgba = try #require(rgba(of: Paint(text)))
      return try #require(ColorMixSpace.oklch.components(ofSRGB: (rgba[0] / 255, rgba[1] / 255, rgba[2] / 255))[2])
    }
    #expect(abs(try hue("color-mix(in oklch, oklch(50% 0.1 none), oklch(50% 0.1 120))") - 120) < 0.5)
    #expect(abs(try hue("color-mix(in oklch, lch(50 30 none), oklch(60% 0.1 120))") - 120) < 0.5)
  }

  @Test("CSS animations and SMIL animations take a missing component from the other color")
  func missingInterpolation() throws {
    let css = parse(
      "<style>@keyframes k { from { fill: rgb(none 0 0) } to { fill: red } } "
        + "rect { animation: k 1s linear }</style>" + #"<rect id="a" width="10" height="10"/>"#)
    let fill = css.at(time: 0.5).root?.elements.first { $0.base.id == "a" }?.style.fill
    #expect(isClose(rgba(of: fill), [255, 0, 0, 1]))
    let smil = parse(
      #"<rect id="a" width="10" height="10"><animate attributeName="fill" from="rgb(none 0 0)" to="red" dur="1s"/></rect>"#)
    let smilFill = smil.at(time: 0.5).root?.elements.first { $0.base.id == "a" }?.style.fill
    #expect(isClose(rgba(of: smilFill), [255, 0, 0, 1]))
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
