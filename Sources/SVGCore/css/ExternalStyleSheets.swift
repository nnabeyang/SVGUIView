@preconcurrency import CoreText
import Foundation
import _CSSParser

/// A style sheet in another file, which an `@import` rule or an `xml-stylesheet` processing instruction reads.
struct ExternalStyleSheet: Sendable, Equatable {
  /// The URL of the file, relative to the document or the style sheet that reads it.
  let href: String
  /// The media queries that the style sheet applies to, or `nil` for all media.
  let media: String?

  /// Whether the style sheet applies to a screen: it has no media queries, or one of them is `all` or `screen`,
  /// optionally after `only`, as Media Queries 4 matches a screen without the features that SVGUIView doesn't know.
  var appliesToScreen: Bool {
    guard let media else { return true }
    return media.split(separator: ",").contains { query in
      let words = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
      let type = words.first == "only" ? words.dropFirst().first : words.first
      // A query with conditions, such as `screen and (min-width: 1px)`, isn't matched.
      return words.count == (words.first == "only" ? 2 : 1) && (type == "all" || type == "screen")
    }
  }
}

/// The style sheets of a document in the order that they cascade in, where some of them are in other files: the
/// style sheets of the `xml-stylesheet` processing instructions, and then each `<style>` element, after the style
/// sheets that its `@import` rules read.
struct StyleSheetSources: Sendable {
  /// A style sheet of a `<style>` element or of a file.
  struct Sheet: Sendable {
    var imports = [ExternalStyleSheet]()
    var rules = [CSSRule]()
    var keyframes = [KeyframesRule]()
    var fontFaces = [FontFaceRule]()

    /// The style sheet of CSS text.
    init(css text: String) {
      var parser = CSSParser(input: Parser(input: ParserInput(input: text)))
      for rule in parser.parseRules() {
        switch rule {
        case .style(let rule): rules.append(rule)
        case .keyframes(let rule): keyframes.append(rule)
        case .import(let sheet): imports.append(sheet)
        case .fontFace(let rule): fontFaces.append(rule)
        case .ignored: break
        }
      }
    }
  }

  var processingInstructions = [ExternalStyleSheet]()
  var sheets = [Sheet]()

  /// Whether a style sheet is in another file, or a style sheet has `@font-face` rules, whose fonts a rendering
  /// reads.
  var hasExternalStyleSheets: Bool {
    !processingInstructions.isEmpty || sheets.contains { !$0.imports.isEmpty || !$0.fontFaces.isEmpty }
  }

  /// The style sheet of the `<style>` elements alone, without the style sheets in other files.
  var stylesheet: Stylesheet {
    var builder = Builder()
    for sheet in sheets { builder.append(sheet, loader: .none) }
    return builder.stylesheet(sources: hasExternalStyleSheets ? self : nil, hasExternalRules: false, fonts: nil)
  }

  /// The deepest chain of style sheets that `@import` rules read.
  static let maxDepth = 3

  /// The style sheet of the document with the style sheets in other files that the loader reads, in their order.
  ///
  /// - Parameter chain: The files of the document and of the style sheets that read the style sheets, which aren't
  ///   read again.
  func resolved(loader: ExternalResourceLoader, chain: [URL]) async -> Stylesheet {
    var builder = Builder()
    for sheet in processingInstructions {
      await builder.append(sheet, loader: loader, chain: chain)
    }
    for sheet in sheets {
      for imported in sheet.imports {
        await builder.append(imported, loader: loader, chain: chain)
      }
      builder.append(sheet, loader: loader)
    }
    let fonts = await builder.fonts()
    return builder.stylesheet(sources: self, hasExternalRules: true, fonts: fonts)
  }

  /// Puts the rules of style sheets in their order, numbered again across the style sheets.
  private struct Builder {
    var rules = [CSSRule]()
    var keyframes = [String: KeyframesRule]()
    /// The `@font-face` rules in their order, with the loaders that read the files of their style sheets.
    var fontFaces = [(rule: FontFaceRule, loader: ExternalResourceLoader)]()

    mutating func append(_ sheet: Sheet, loader: ExternalResourceLoader) {
      fontFaces += sheet.fontFaces.map { ($0, loader) }
      for var rule in sheet.rules {
        rule.sourceOrder = rules.count
        rules.append(rule)
      }
      // Of the `@keyframes` rules with the same name, the last one wins.
      for rule in sheet.keyframes {
        keyframes[rule.name] = rule
      }
    }

    /// Appends a style sheet in another file, after the style sheets that its own `@import` rules read. A style sheet
    /// that doesn't apply to a screen, that the loader doesn't read, or that the chain already reads, is left out.
    mutating func append(_ external: ExternalStyleSheet, loader: ExternalResourceLoader, chain: [URL]) async {
      guard external.appliesToScreen, chain.count <= StyleSheetSources.maxDepth,
        let file = loader.resourceURL(ofHref: external.href), !chain.contains(file),
        let data = await loader.data(forHref: external.href)
      else { return }
      let sheet = Sheet(css: String(decoding: data, as: UTF8.self))
      let rebased = loader.rebased(to: file)
      for imported in sheet.imports {
        await append(imported, loader: rebased, chain: chain + [file])
      }
      append(sheet, loader: rebased)
    }

    /// The fonts that the `@font-face` rules read: each rule reads the first of its sources that Core Text reads, a
    /// file that its loader reads, a data URL or a font of the system. A rule that reads none is left out.
    func fonts() async -> DocumentFonts? {
      var faces = [DocumentFonts.Face]()
      for (rule, loader) in fontFaces {
        for source in rule.sources {
          let descriptor: CTFontDescriptor?
          switch source {
          case .url(let url, _) where url.lowercased().hasPrefix("data:"):
            descriptor = EmbeddedImage.data(ofHref: url).flatMap(DocumentFonts.descriptor(of:))
          case .url(let url, _):
            descriptor = await loader.data(forHref: url).flatMap(DocumentFonts.descriptor(of:))
          case .local(let name):
            descriptor = DocumentFonts.descriptor(ofLocal: name)
          }
          if let descriptor {
            faces.append(
              DocumentFonts.Face(
                family: rule.family.lowercased(), weight: rule.weight, style: rule.style, descriptor: descriptor))
            break
          }
        }
      }
      return faces.isEmpty ? nil : DocumentFonts(faces: faces)
    }

    func stylesheet(sources: StyleSheetSources?, hasExternalRules: Bool, fonts: DocumentFonts?) -> Stylesheet {
      Stylesheet(
        rules: rules, keyframes: keyframes, sources: sources, hasExternalRules: hasExternalRules, fonts: fonts)
    }
  }
}

extension SVGBaseContext {
  /// Whether the document reads style sheets in other files, which ``resolvingExternalStyleSheets(loader:at:)``
  /// reads.
  package var needsExternalStyleSheets: Bool {
    stylesheet.sources != nil && !stylesheet.hasExternalRules
  }

  /// Whether another context is of the same document, without the changes that the document API made since.
  package func hasSameDocument(as other: SVGBaseContext) -> Bool {
    document.root === other.document.root
  }

  /// Whether the cascade has the rules of the style sheets in other files that a loader read.
  package var hasExternalStyleSheets: Bool {
    stylesheet.hasExternalRules
  }

  /// The context with the style sheets in other files that the loader reads, in the order that they cascade in, and
  /// the computed values of the elements with them, or this context if it reads none. The animations keep how they
  /// play and the times that the document API begins and ends them at.
  ///
  /// - Parameter time: The time of the document in seconds, which the CSS animations that the new style sheets start
  ///   start at.
  package func resolvingExternalStyleSheets(loader: ExternalResourceLoader, at time: Double = 0) async
    -> SVGBaseContext
  {
    guard needsExternalStyleSheets, let sources = stylesheet.sources else { return self }
    let resolved = await sources.resolved(
      loader: loader, chain: loader.resolvedBaseURL.map { [$0] } ?? [])
    guard !Task.isCancelled else { return self }
    return replacingStylesheet(resolved, at: time)
  }

  /// The context with the style sheets of another context of the same document, which read the style sheets in other
  /// files, such as a context that ``resolvingExternalStyleSheets(loader:at:)`` made before the document changed.
  package func adoptingStyleSheets(of other: SVGBaseContext, at time: Double) -> SVGBaseContext {
    replacingStylesheet(other.stylesheet, at: time)
  }

  /// The context without the rules of the style sheets in other files, which the next rendering reads again, such as
  /// after the files that a view reads change.
  package func unresolvingExternalStyleSheets(at time: Double) -> SVGBaseContext {
    guard stylesheet.hasExternalRules, let sources = stylesheet.sources else { return self }
    return replacingStylesheet(sources.stylesheet, at: time)
  }
}
