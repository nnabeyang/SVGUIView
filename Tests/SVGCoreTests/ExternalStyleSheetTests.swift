import CoreText
import Foundation
import Testing

@testable import SVGCore

/// A folder of files in the temporary folder, which is removed when it's released.
private final class Files {
  let url: URL

  init(_ files: [String: String]) throws {
    url = FileManager.default.temporaryDirectory.appending(path: "ExternalStyleSheets-\(UUID().uuidString)")
    for (path, text) in files {
      let file = url.appending(path: path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: file)
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

@Suite("Style sheets in other files")
struct ExternalStyleSheetTests {
  /// The names of the fill colors of the elements with IDs of a document of a folder, by their IDs, after the style
  /// sheets in other files are read.
  private func fills(of path: String, in files: Files, ids: [String]) async throws -> [String: String] {
    let url = files.url.appending(path: path)
    let base = SVGParser.parse(data: try Data(contentsOf: url))
    let loader = ExternalResourceLoader(baseURL: url, folder: files.url, cache: ExternalResourceCache())
    let resolved = await base.resolvingExternalStyleSheets(loader: loader)
    #expect(!resolved.needsExternalStyleSheets)
    var fills = [String: String]()
    for id in ids {
      if case .color(let color) = try #require(resolved[id]).style.fill { fills[id] = color.description }
    }
    return fills
  }

  @Test("@import rules before the other rules are kept with their media, and later ones are dropped")
  func importRules() {
    let sheet = StyleSheetSources.Sheet(
      css: #"@import url(a.css); @import "b.css" screen; rect { fill: red } @import url(c.css);"#)
    #expect(sheet.imports == [ExternalStyleSheet(href: "a.css", media: nil), ExternalStyleSheet(href: "b.css", media: "screen")])
    #expect(sheet.rules.count == 1)
  }

  @Test(
    "a style sheet applies to a screen without media queries, or with all or screen",
    arguments: [
      (nil, true), ("all", true), ("screen", true), ("only screen", true), ("print, Screen", true), ("print", false),
      ("screen and (min-width: 1px)", false), ("not screen", false),
    ] as [(String?, Bool)])
  func media(media: String?, applies: Bool) {
    #expect(ExternalStyleSheet(href: "a.css", media: media).appliesToScreen == applies)
  }

  @Test("xml-stylesheet processing instructions before the root read style sheets of CSS that aren't alternates")
  func processingInstructions() throws {
    let svg = """
      <?xml version="1.0"?>
      <?xml-stylesheet href="a.css" type="text/css"?>
      <?xml-stylesheet href='b.css' media="print"?>
      <?xml-stylesheet href="c.css" type="text/xsl"?>
      <?xml-stylesheet href="d.css" alternate="yes"?>
      <svg xmlns="http://www.w3.org/2000/svg"><?xml-stylesheet href="e.css"?></svg>
      """
    let base = SVGParser.parse(data: Data(svg.utf8))
    #expect(base.needsExternalStyleSheets)
    let sheets = try #require(base.stylesheet.sources).processingInstructions
    #expect(sheets == [ExternalStyleSheet(href: "a.css", media: nil), ExternalStyleSheet(href: "b.css", media: "print")])
  }

  @Test("a document without style sheets in other files doesn't read any")
  func noExternalStyleSheets() {
    let base = SVGParser.parse(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"><style>a {}</style></svg>"#.utf8))
    #expect(!base.needsExternalStyleSheets)
    #expect(base.stylesheet.sources?.hasExternalStyleSheets == nil)
  }

  @Test(
    "the style sheets in other files cascade in their order: processing instructions, then imports before the rules of their style elements"
  )
  func order() async throws {
    let files = try Files([
      "docs/doc.svg": """
      <?xml-stylesheet href="pi.css"?>
      <svg xmlns="http://www.w3.org/2000/svg">
        <style>@import url(imported.css); #b { fill: lime }</style>
        <rect id="a"/><rect id="b"/><rect id="c"/><rect id="d"/>
      </svg>
      """,
      "docs/pi.css": "#a, #b, #c, #d { fill: red } #c { fill: blue }",
      "docs/imported.css": "@import url(nested/deep.css); #a, #b { fill: yellow }",
      "docs/nested/deep.css": "#d { fill: green } #a { fill: red }",
    ])
    let fills = try await fills(of: "docs/doc.svg", in: files, ids: ["a", "b", "c", "d"])
    // The imported style sheet wins over the processing instruction, and loses to the rules of its style element.
    #expect(fills == ["a": "yellow", "b": "lime", "c": "blue", "d": "green"])
  }

  @Test("style sheets that read themselves again, that don't apply to a screen, or outside the folder aren't read")
  func unread() async throws {
    let files = try Files([
      "docs/doc.svg": """
      <svg xmlns="http://www.w3.org/2000/svg">
        <style>@import url(a.css); @import url(print.css) print; @import url(../outside.css);</style>
        <rect id="r" fill="lime"/>
      </svg>
      """,
      "docs/a.css": "@import url(b.css);",
      "docs/b.css": "@import url(a.css); @import url(doc.svg);",
      "docs/print.css": "#r { fill: red }",
      "outside.css": "#r { fill: red }",
    ])
    let url = files.url.appending(path: "docs/doc.svg")
    let base = SVGParser.parse(data: try Data(contentsOf: url))
    let loader = ExternalResourceLoader(
      baseURL: url, folder: files.url.appending(path: "docs"), cache: ExternalResourceCache())
    let resolved = await base.resolvingExternalStyleSheets(loader: loader)
    let element = try #require(resolved["r"])
    let color = try #require(element.style.fill.color, "fill isn't a color")
    #expect(color.description == "lime")
  }

  @Test("the style sheets in other files are read again after the context gives them up")
  func unresolving() async throws {
    let files = try Files([
      "doc.svg": #"<svg xmlns="http://www.w3.org/2000/svg"><style>@import url(a.css);</style><rect id="r"/></svg>"#,
      "a.css": "#r { fill: lime }",
    ])
    let url = files.url.appending(path: "doc.svg")
    let base = SVGParser.parse(data: try Data(contentsOf: url))
    let loader = ExternalResourceLoader(baseURL: url, folder: files.url, cache: ExternalResourceCache())
    let resolved = await base.resolvingExternalStyleSheets(loader: loader)
    #expect(resolved.hasExternalStyleSheets)
    let unresolved = resolved.unresolvingExternalStyleSheets(at: 0)
    #expect(unresolved.needsExternalStyleSheets)
    #expect(!unresolved.hasExternalStyleSheets)
  }

  @Test("@font-face rules keep their family, their sources of supported formats, their weights and their style")
  func fontFaceRules() throws {
    let sheet = StyleSheetSources.Sheet(
      css: """
        @font-face {
          font-family: "My Font"; font-weight: 300 600; font-style: italic;
          src: url(a.woff) format("woff"), url(b.svg) format("svg"), local(Helvetica Bold), url(c.ttf);
        }
        @font-face { src: url(x.woff) }
        @font-face { font-family: A; src: url("data:font/woff;base64,AA==") format(woff); font-weight: bold }
        """)
    try #require(sheet.fontFaces.count == 2)
    let first = sheet.fontFaces[0]
    #expect(first.family == "My Font")
    #expect(first.sources == [.url("a.woff", format: "woff"), .local("Helvetica Bold"), .url("c.ttf", format: nil)])
    #expect(first.weight == 300...600)
    #expect(first.style == .italic)
    #expect(sheet.fontFaces[1].family == "A")
    #expect(sheet.fontFaces[1].weight == 700...700)
    #expect(sheet.fontFaces[1].style == .normal)
  }

  @Test(
    "a family of fonts gives the weight that CSS Fonts 4 matches",
    arguments: [(600, "Helvetica-Bold"), (900, "Helvetica-Bold"), (450, "Helvetica"), (400, "Helvetica"), (350, "Helvetica-Light"), (100, "Helvetica-Light")])
  func weights(weight: Double, expected: String) throws {
    func face(_ name: String, _ weight: Double) -> DocumentFonts.Face {
      DocumentFonts.Face(
        family: "test", weight: weight...weight, style: .normal,
        descriptor: CTFontDescriptorCreateWithNameAndSize(name as CFString, 0))
    }
    let fonts = DocumentFonts(faces: [face("Helvetica-Light", 300), face("Helvetica", 400), face("Helvetica-Bold", 700)])
    let request = FontSelectionRequest(
      weight: FontSelectionValue(weight), width: .normalStretchValue, slope: .normalItalicValue)
    let font = try #require(fonts.font(family: "Test", request: request, size: 10))
    #expect(CTFontCopyPostScriptName(font) as String == expected)
    #expect(fonts.font(family: "other", request: request, size: 10) == nil)
  }

  @Test("the fonts of the @font-face rules of a document are found in the document, and not in another one")
  func documentFonts() async throws {
    func font(of svg: String, resolving: Bool) async throws -> String {
      var base = SVGParser.parse(data: Data(svg.utf8))
      if resolving { base = await base.resolvingExternalStyleSheets(loader: .none) }
      let text = try #require(base["t"])
      let context = ResolveContext(
        base: base, viewPort: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 1,
        viewBox: CGRect(x: 0, y: 0, width: 10, height: 10))
      return CTFontCopyPostScriptName(text.style.font.ctFont(context: context)) as String
    }
    let declared = #"<style>@font-face { font-family: Shown; src: local("Helvetica-Bold") }</style>"#
    let text = #"<text id="t" font-family="Shown, Courier">a</text>"#
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"#
    #expect(try await font(of: svg + declared + text + "</svg>", resolving: true) == "Helvetica-Bold")
    // Another document without the rule finds the next family.
    #expect(try await font(of: svg + text + "</svg>", resolving: false) == "Courier")
    #expect(SVGParser.parse(data: Data((svg + declared + "</svg>").utf8)).needsExternalStyleSheets)
  }
}
