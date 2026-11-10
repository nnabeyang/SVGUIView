import Foundation
import _CSSParser
import os

enum SVGElementName: String, Equatable {
  case svg
  case g
  case a
  case text
  case tspan
  case textPath
  case image
  case line
  case circle
  case ellipse
  case rect
  case path
  case polyline
  case polygon
  case style
  case linearGradient
  case radialGradient
  case stop
  case use
  case defs
  case symbol
  case `switch`
  case clipPath
  case mask
  case marker
  case pattern
  case filter
  case feGaussianBlur
  case feImage
  case feFlood
  case feBlend
  case feColorMatrix
  case feComponentTransfer
  case feComposite
  case feConvolveMatrix
  case feMorphology
  case feTile
  case feTurbulence
  case feDiffuseLighting
  case feDisplacementMap
  case feDistantLight
  case feDropShadow
  case feFuncR
  case feFuncG
  case feFuncB
  case feFuncA
  case feOffset
  case fePointLight
  case feSpecularLighting
  case feSpotLight
  case feMerge
  case feMergeNode
  case animate
  case set
  case animateTransform
  case animateMotion
  case mpath
  case unknown

  /// Whether the element is a SMIL animation element.
  var isAnimation: Bool {
    switch self {
    case .animate, .set, .animateTransform, .animateMotion: true
    default: false
    }
  }

  /// Whether the element is made into the tree of elements to render: rendered, used by rendered elements, or
  /// holding elements that can be referenced. `<style>` and the elements of SMIL animation aren't.
  var isRendered: Bool {
    switch self {
    case .style, .animate, .set, .animateTransform, .animateMotion, .mpath: false
    default: true
    }
  }
}

enum SVGXmlNameSpace: String {
  case svg = "http://www.w3.org/2000/svg"
  case xlink = "http://www.w3.org/1999/xlink"
}

package final class SVGParser: NSObject {
  /// An element whose end tag the parser hasn't reached yet.
  private struct OpenElement {
    let id: ElementID
    let name: SVGElementName
    let localName: String
    let attributes: [String: String]
    var children: [DocumentElement] = []
    /// The character data so far before each child and after the last one, which only `<text>`, `<tspan>`,
    /// `<textPath>`, `<a>` and `<style>` keep. An `<a>` uses it only in text.
    var texts = [""]

    var keepsText: Bool { name == .text || name == .tspan || name == .textPath || name == .a || name == .style }
  }

  /// The style sheets of the document, in the order that they cascade in.
  private var styleSources = StyleSheetSources()
  private var stack = [OpenElement]()
  private var root: DocumentElement?
  private var elementCount = 0
  /// The namespaces that each prefix is bound to, innermost last, or `nil` for a namespace other than SVG and XLink.
  private var nameSpaces = [String: [SVGXmlNameSpace?]]()

  private static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "parser")

  /// Parses a document.
  ///
  /// - Parameter languages: The languages of the user, in the order of preference, which `systemLanguage` matches.
  package static func parse(data: Data, languages: [String] = Locale.preferredLanguages) -> SVGBaseContext {
    let parser = SVGParser()
    return parser.parse(data: data, languages: languages)
  }

  private func parse(parser: XMLParser, languages: [String]) -> SVGBaseContext {
    parser.delegate = self
    parser.parse()
    return SVGBaseContext(
      document: DocumentTree(root: root, languages: languages), stylesheet: styleSources.stylesheet)
  }

  private func parse(data: Data, languages: [String]) -> SVGBaseContext {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    return parse(parser: parser, languages: languages)
  }
}

extension SVGParser: XMLParserDelegate {
  private func filter(attributes oldValue: [String: String]) -> [String: String] {
    var attributes = [String: String]()
    for element in oldValue {
      let a = element.key.components(separatedBy: ":")
      guard a.count == 2 else {
        attributes[element.key] = element.value
        continue
      }
      let prefix = a[0]
      let attributeName = a[1]
      if case .xlink = nameSpaces[prefix]?.last, attributeName == "href" {
        attributes[attributeName] = element.value
      } else if prefix == "xml", attributeName == "space" || attributeName == "lang" {
        // The `xml` prefix is bound without a declaration, so the parser doesn't report it.
        attributes[element.key] = element.value
      }
    }
    return attributes
  }

  package func parser(_: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
    let name = SVGXmlNameSpace(rawValue: namespaceURI ?? "") == .svg ? (SVGElementName(rawValue: elementName) ?? .unknown) : .unknown
    // The character data after this child goes after it.
    if !stack.isEmpty {
      stack[stack.count - 1].texts.append("")
    }
    stack.append(OpenElement(id: ElementID(rawValue: elementCount), name: name, localName: elementName, attributes: attributeDict))
    elementCount += 1
  }

  /// An `xml-stylesheet` processing instruction before the root element reads a style sheet in another file, as
  /// Associating Style Sheets with XML Documents describes: one of CSS, or without a type, that isn't an alternate
  /// style sheet.
  package func parser(_: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
    guard target == "xml-stylesheet", stack.isEmpty, root == nil, let data else { return }
    let attributes = Self.pseudoAttributes(data)
    guard let href = attributes["href"], !href.isEmpty,
      ["text/css", nil].contains(attributes["type"]?.trimmingCharacters(in: .whitespaces).lowercased()),
      attributes["alternate"] != "yes"
    else { return }
    let media = attributes["media"]?.trimmingCharacters(in: .whitespaces)
    styleSources.processingInstructions.append(
      ExternalStyleSheet(href: href, media: media?.isEmpty == false ? media : nil))
  }

  /// The pseudo-attributes of a processing instruction, such as `href="a.css"`, with their values unescaped.
  static func pseudoAttributes(_ data: String) -> [String: String] {
    var attributes = [String: String]()
    var rest = Substring(data)
    while let equals = rest.firstIndex(of: "=") {
      let name = rest[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
      var value = rest[rest.index(after: equals)...].drop(while: \.isWhitespace)
      guard let quote = value.first, quote == "\"" || quote == "'" else { break }
      value = value.dropFirst()
      guard let end = value.firstIndex(of: quote) else { break }
      attributes[name] = String(value[..<end])
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
      rest = value[value.index(after: end)...]
    }
    return attributes
  }

  // A prefix bound to another namespace inside the scope of a binding, such as `xlink` bound to another URI, hides
  // the outer binding until the inner one ends.
  package func parser(_: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
    nameSpaces[prefix, default: []].append(SVGXmlNameSpace(rawValue: namespaceURI))
  }

  package func parser(_: XMLParser, didEndMappingPrefix prefix: String) {
    nameSpaces[prefix]?.removeLast()
    if nameSpaces[prefix]?.isEmpty == true {
      nameSpaces.removeValue(forKey: prefix)
    }
  }

  package func parser(_: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
    let name = SVGXmlNameSpace(rawValue: namespaceURI ?? "") == .svg ? (SVGElementName(rawValue: elementName) ?? .unknown) : .unknown
    guard let open = stack.popLast() else { return }
    precondition(name == open.name)
    // A style sheet whose type isn't CSS isn't read.
    if open.name == .style,
      ["", "text/css"].contains(open.attributes["type", default: ""].trimmingCharacters(in: .whitespaces).lowercased())
    {
      // The rules are numbered in document order across `<style>` elements, so that a later rule wins a tie.
      styleSources.sheets.append(StyleSheetSources.Sheet(css: open.texts.joined()))
    }
    let element = DocumentElement(
      id: open.id, name: open.name, localName: open.localName, attributes: filter(attributes: open.attributes),
      texts: open.texts, children: open.children)
    if stack.isEmpty {
      root = element
    } else {
      stack[stack.count - 1].children.append(element)
    }
  }

  package func parser(_: XMLParser, foundCharacters fragment: String) {
    guard let last = stack.indices.last, stack[last].keepsText else { return }
    stack[last].texts[stack[last].texts.count - 1].append(fragment)
  }

  package func parser(_: XMLParser, parseErrorOccurred parseError: any Error) {
    Self.logger.error("\(parseError.localizedDescription)")
  }
}
