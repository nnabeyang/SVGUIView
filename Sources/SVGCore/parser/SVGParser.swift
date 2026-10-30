import Foundation
import _CSSParser
import os

enum SVGElementName: String, Equatable {
  case svg
  case g
  case text
  case tspan
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
  case clipPath
  case mask
  case marker
  case pattern
  case filter
  case feGaussianBlur
  case feFlood
  case feBlend
  case feOffset
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

  /// Whether the element is rendered or used by rendered elements. `<style>`, unknown elements and the elements of
  /// SMIL animation aren't.
  var isRendered: Bool {
    switch self {
    case .style, .unknown, .animate, .set, .animateTransform, .animateMotion, .mpath: false
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
    /// The character data so far before each child and after the last one, which only `<text>`, `<tspan>` and
    /// `<style>` keep.
    var texts = [""]

    var keepsText: Bool { name == .text || name == .tspan || name == .style }
  }

  private var rules: [CSSRule] = []
  private var keyframes: [String: KeyframesRule] = [:]
  private var stack = [OpenElement]()
  private var root: DocumentElement?
  private var elementCount = 0
  private var nameSpaces = [String: (ns: SVGXmlNameSpace, count: Int)]()

  private static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "parser")

  package static func parse(data: Data) -> SVGBaseContext {
    let parser = SVGParser()
    return parser.parse(data: data)
  }

  private func parse(parser: XMLParser) -> SVGBaseContext {
    parser.delegate = self
    parser.parse()
    return SVGBaseContext(
      document: DocumentTree(root: root), stylesheet: Stylesheet(rules: rules, keyframes: keyframes))
  }

  private func parse(data: Data) -> SVGBaseContext {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    return parse(parser: parser)
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
      if case .xlink = nameSpaces[prefix]?.ns, attributeName == "href" {
        attributes[attributeName] = element.value
      } else if prefix == "xml", attributeName == "space" {
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

  package func parser(_: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
    guard let nameSpace = SVGXmlNameSpace(rawValue: namespaceURI) else { return }
    if let value = nameSpaces[prefix] {
      nameSpaces[prefix] = (ns: nameSpace, value.count + 1)
    } else {
      nameSpaces[prefix] = (ns: nameSpace, 1)
    }
  }

  package func parser(_: XMLParser, didEndMappingPrefix prefix: String) {
    if let value = nameSpaces[prefix], value.count > 1 {
      nameSpaces[prefix] = (ns: value.ns, count: value.count - 1)
    } else {
      nameSpaces.removeValue(forKey: prefix)
    }
  }

  package func parser(_: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
    let name = SVGXmlNameSpace(rawValue: namespaceURI ?? "") == .svg ? (SVGElementName(rawValue: elementName) ?? .unknown) : .unknown
    guard let open = stack.popLast() else { return }
    precondition(name == open.name)
    if open.name == .style {
      let parseInput = ParserInput(input: open.texts.joined())
      let input = Parser(input: parseInput)
      var parser = CSSParser(input: input)
      // Number the rules in document order across `<style>` elements, so that a later rule wins a tie.
      let offset = rules.count
      for rule in parser.parseRules() {
        switch rule {
        case .style(var rule):
          rule.sourceOrder += offset
          rules.append(rule)
        case .keyframes(let rule):
          keyframes[rule.name] = rule
        case .ignored:
          break
        }
      }
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
