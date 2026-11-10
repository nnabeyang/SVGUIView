// CoreText doesn't mark its immutable types, such as CTFontDescriptor, Sendable, though they can be used across
// threads.
@preconcurrency import CoreText
import Foundation
import _CSSParser

/// An `@font-face` rule: a font in another file or of the system, which `font-family` names.
struct FontFaceRule: Sendable, Equatable {
  /// Where a font can be read.
  enum Source: Sendable, Equatable {
    /// A file or a data URL, with the format that the rule gives it, in lowercase, or `nil`.
    case url(String, format: String?)
    /// A font of the system by its name.
    case local(String)
  }

  enum Style: Sendable, Equatable {
    case normal
    case italic
    case oblique
  }

  /// The family, as `font-family` names it.
  let family: String
  /// The sources in their order of preference.
  let sources: [Source]
  /// The weights that the font has.
  let weight: ClosedRange<Double>
  let style: Style

  /// The formats of fonts that Core Text reads.
  static let supportedFormats: Set<String> = ["woff", "woff2", "truetype", "opentype", "collection"]

  /// The rule of the descriptors of an `@font-face` block, by their names in lowercase, or `nil` if it has no family
  /// or no sources, which make it invalid.
  init?(descriptors: [String: String]) {
    guard let family = descriptors["font-family"].flatMap(Self.family), let src = descriptors["src"] else {
      return nil
    }
    let sources = Self.sources(src)
    guard !sources.isEmpty else { return nil }
    self.family = family
    self.sources = sources
    weight = descriptors["font-weight"].flatMap(Self.weight) ?? 400...400
    style =
      switch descriptors["font-style"]?.split(whereSeparator: \.isWhitespace).first?.lowercased() {
      case "italic": .italic
      case "oblique": .oblique
      default: .normal
      }
  }

  /// A family name: a string, or identifiers separated by spaces.
  private static func family(_ text: String) -> String? {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    if case .success(let name) = input.tryParse({ input in input.expectString() }), input.isExhausted() {
      return name
    }
    var names = [String]()
    while !input.isExhausted() {
      guard case .success(let name) = input.expectIdent() else { return nil }
      names.append(name)
    }
    return names.isEmpty ? nil : names.joined(separator: " ")
  }

  /// The sources of `src`: `url(…)` with an optional `format(…)`, and `local(…)`, separated by commas. A source
  /// that isn't valid, or of a format that Core Text doesn't read, is left out.
  private static func sources(_ text: String) -> [Source] {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    let parsed = input.parseCommaSeparated { input -> Result<Source?, CSSParseError> in
      if case .success(let url) = input.tryParse({ input in input.expectUrl() }) {
        var format: String?
        if case .success = input.tryParse({ input in input.expectFunctionMatching(expectedName: "format") }) {
          let result: Result<String, CSSParseError> = input.parseNestedBlock { input in
            input.expectIdentOrString().mapError { $0.into() }
          }
          guard case .success(let name) = result else { return .success(nil) }
          format = name.lowercased()
        }
        // Technologies such as `tech(variations)` aren't read, and make the source not supported.
        guard input.isExhausted() else { return .success(nil) }
        if let format, !supportedFormats.contains(format) { return .success(nil) }
        return .success(.url(url, format: format))
      }
      if case .success = input.tryParse({ input in input.expectFunctionMatching(expectedName: "local") }) {
        let result: Result<String, CSSParseError> = input.parseNestedBlock { input in
          if case .success(let name) = input.tryParse({ input in input.expectString() }) { return .success(name) }
          var names = [String]()
          while !input.isExhausted() {
            guard case .success(let name) = input.expectIdent() else {
              return .failure(input.newCustomError(error: StyleParseErrorKind.invalid))
            }
            names.append(name)
          }
          return .success(names.joined(separator: " "))
        }
        guard case .success(let name) = result, !name.isEmpty, input.isExhausted() else { return .success(nil) }
        return .success(.local(name))
      }
      while case .success = input.next() {}
      return .success(nil)
    }
    guard case .success(let sources) = parsed else { return [] }
    return sources.compactMap { $0 }
  }

  /// The weights of `font-weight`: `normal`, `bold`, a number from 1 to 1000, or a range of two of them.
  private static func weight(_ text: String) -> ClosedRange<Double>? {
    let values = text.split(whereSeparator: \.isWhitespace).map { word -> Double? in
      switch word.lowercased() {
      case "normal": 400
      case "bold": 700
      default: Double(word).flatMap { (1...1000).contains($0) ? $0 : nil }
      }
    }
    guard !values.isEmpty, values.count <= 2, values.allSatisfy({ $0 != nil }) else { return nil }
    let weights = values.compactMap { $0 }
    return weights.min()!...weights.max()!
  }
}

/// Reads the descriptors in the block of an `@font-face` rule, each as its text.
struct FontFaceDescriptorParser: RuleBodyItemParser {
  typealias Declaration = (name: String, value: String)
  typealias Prelude = Void
  typealias QualifiedRule = (name: String, value: String)
  typealias AtRule = (name: String, value: String)
  typealias Error = StyleParseErrorKind

  func parseDeclarations() -> Bool {
    true
  }

  func parseQualified() -> Bool {
    false
  }

  mutating func parseValue(
    name: String, input: inout _CSSParser.Parser, declarationStart _: inout ParserState
  ) -> Result<(name: String, value: String), CSSParseError> {
    let start = input.position
    while case .success = input.next() {}
    return .success((name.lowercased(), input.slice(from: start).trimmingCharacters(in: .whitespacesAndNewlines)))
  }

  /// The descriptors of a block, by their names in lowercase. Of the descriptors with the same name, the last one
  /// wins.
  static func descriptors(in input: inout _CSSParser.Parser) -> [String: String] {
    var bodyParser: RuleBodyParser<FontFaceDescriptorParser, (name: String, value: String), StyleParseErrorKind> =
      RuleBodyParser(input: input, parser: FontFaceDescriptorParser())
    var descriptors = [String: String]()
    while let item = bodyParser.next() {
      if case .success(let descriptor) = item { descriptors[descriptor.name] = descriptor.value }
    }
    input = bodyParser.input
    return descriptors
  }
}

/// The fonts that the `@font-face` rules of a document read, which `font-family` finds before the fonts of the
/// system. They aren't registered with the system, so another document doesn't find them.
final class DocumentFonts: Sendable {
  /// A font that a rule read, with the weights and the style that the rule gives it.
  struct Face: Sendable {
    /// The family in lowercase, as families are found regardless of their case.
    let family: String
    let weight: ClosedRange<Double>
    let style: FontFaceRule.Style
    let descriptor: CTFontDescriptor
  }

  let faces: [Face]

  init(faces: [Face]) {
    self.faces = faces
  }

  /// The font of a family at a size that best matches a request of a weight and a style, as CSS Fonts 4 matches
  /// fonts, or `nil` if no rule reads a font of the family.
  func font(family: String, request: FontSelectionRequest, size: Double) -> CTFont? {
    let family = family.lowercased()
    let candidates = faces.filter { $0.family == family }
    guard !candidates.isEmpty else { return nil }
    let capabilities = candidates.map { face in
      let capabilities = FontSelectionCapabilities()
      capabilities.weight = FontSelectionValue(face.weight.lowerBound)...FontSelectionValue(face.weight.upperBound)
      let slope = face.style == .normal ? FontSelectionValue.normalItalicValue : .italicValue
      capabilities.slope = slope...slope
      return capabilities
    }
    let bounds = FontSelectionCapabilities()
    bounds.weight = capabilities[0].weight
    bounds.slope = capabilities[0].slope
    for capability in capabilities.dropFirst() {
      bounds.expand(other: capability)
    }
    let algorithm = FontSelectionAlgorithm(request: request, capabilities: capabilities, capabilitiesBounds: bounds)
    guard let index = algorithm.indexOfBestCapabilities(), index < candidates.count else { return nil }
    return CTFontCreateWithFontDescriptor(candidates[index].descriptor, size, nil)
  }

  /// The font that a source gives, or `nil` if Core Text doesn't read it.
  static func descriptor(of data: Data) -> CTFontDescriptor? {
    CTFontManagerCreateFontDescriptorFromData(data as CFData)
  }

  /// The font of the system that a name names, by its full name or its PostScript name, or `nil` if there is none.
  static func descriptor(ofLocal name: String) -> CTFontDescriptor? {
    let font = CTFontCreateWithName(name as CFString, 0, nil)
    let names = [CTFontCopyPostScriptName(font), CTFontCopyFullName(font)].map { ($0 as String).lowercased() }
    return names.contains(name.lowercased()) ? CTFontCopyFontDescriptor(font) : nil
  }
}

/// Finds the fonts that the `@font-face` rules of a document read before the fonts of the system.
final class DocumentFontSelector: CSSFontSelector {
  private let fonts: DocumentFonts

  init(fonts: DocumentFonts) {
    self.fonts = fonts
    super.init()
  }

  override func fontRangesForFamily(fontDescription: FontDescription, familyName: String) -> FontRanges {
    if let font = fonts.font(
      family: familyName, request: fontDescription.fontSelectionRequest, size: fontDescription.computedSize)
    {
      return FontRanges(
        font: Font(platformData: FontPlatformData(font: font, size: fontDescription.computedSize), origin: .remote))
    }
    return super.fontRangesForFamily(fontDescription: fontDescription, familyName: familyName)
  }
}
