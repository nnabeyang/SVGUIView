import Foundation
import _CSSParser
import os

enum SVGElementName: String, Equatable {
  case svg
  case g
  case text
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
  case pattern
  case filter
  case feGaussianBlur
  case feFlood
  case feBlend
  case feOffset
  case feMerge
  case feMergeNode
  case unknown
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
  }

  private var pservers: [String: any SVGGradientServer] = [:]
  private var rules: [CSSRule] = []
  private var stack = [OpenElement]()
  private var root: DocumentElement?
  private var elementCount = 0
  private var text: String = ""
  private var nameSpaces = [String: (ns: SVGXmlNameSpace, count: Int)]()

  private static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "parser")

  package static func parse(data: Data) -> SVGBaseContext {
    let parser = SVGParser()
    return parser.parse(data: data)
  }

  private func parse(parser: XMLParser) -> SVGBaseContext {
    parser.delegate = self
    parser.parse()
    var contentIdMap: [String: ObjectIdentifier] = [:]
    var contentsMap: [ObjectIdentifier: any SVGElement] = [:]
    let document = SVGDocument(root: root)
    let css = Stylesheet(rules: rules)
    guard let documentRoot = root,
      let root = ElementCursor(root: documentRoot).makeElement(with: css) as? SVGSVGElement
    else {
      return SVGBaseContext(
        document: document, root: nil, pservers: pservers, contentIdMap: contentIdMap, contents: contentsMap)
    }

    let contents = root.elements
    for content in contents {
      let identifier = content.index
      contentsMap[identifier] = content
      switch content {
      case let content as any SVGDrawableElement:
        if let id = content.id,
          contentIdMap[id] == nil
        {
          contentIdMap[id] = identifier
        }
      case let pserver as any SVGGradientServer:
        if let id = pserver.id, pservers[id] == nil {
          pservers[id] = pserver
        }
      default:
        break
      }
    }

    var context = SVGBaseContext(
      document: document, root: root, pservers: pservers, contentIdMap: contentIdMap, contents: contentsMap)

    root.clip(context: &context)
    root.mask(context: &context)
    root.pattern(context: &context)
    root.filter(context: &context)
    return context
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
      }
    }
    return attributes
  }

  package func parser(_: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
    let name = SVGXmlNameSpace(rawValue: namespaceURI ?? "") == .svg ? (SVGElementName(rawValue: elementName) ?? .unknown) : .unknown
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
      let parseInput = ParserInput(input: text)
      let input = Parser(input: parseInput)
      var parser = CSSParser(input: input)
      // Number the rules in document order across `<style>` elements, so that a later rule wins a tie.
      let offset = rules.count
      rules.append(
        contentsOf: parser.parseRules().map {
          var rule = $0
          rule.sourceOrder += offset
          return rule
        })
    }
    let element = DocumentElement(
      id: open.id, name: open.name, localName: open.localName, attributes: filter(attributes: open.attributes),
      text: text, children: open.children)
    text = ""
    if stack.isEmpty {
      root = element
    } else {
      stack[stack.count - 1].children.append(element)
    }
  }

  package func parser(_: XMLParser, foundCharacters fragment: String) {
    switch stack.last?.name {
    case .text, .style:
      text.append(fragment)
    default:
      break
    }
  }

  package func parser(_: XMLParser, parseErrorOccurred parseError: any Error) {
    Self.logger.error("\(parseError.localizedDescription)")
  }
}
