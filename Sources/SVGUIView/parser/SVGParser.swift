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

final class SVGParser: NSObject {
  private var pservers: [String: any SVGGradientServer] = [:]
  private var rules: [CSSRule] = []
  private var contents: [SVGBaseElement] = []
  private var contentIds: [Int] = []
  private var countList = [Int]()
  private var stack = [(name: SVGElementName, attributes: [String: String])]()
  private var text: String = ""
  private var nameSpaces = [String: (ns: SVGXmlNameSpace, count: Int)]()

  private static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "parser")

  static func parse(data: Data) -> SVGBaseContext {
    let parser = SVGParser()
    return parser.parse(data: data)
  }

  private func parse(parser: XMLParser) -> SVGBaseContext {
    parser.delegate = self
    parser.parse()
    var contentIdMap: [String: ObjectIdentifier] = [:]
    var contentsMap: [ObjectIdentifier: any SVGElement] = [:]
    guard let rootNode = contents.last else {
      return SVGBaseContext(root: nil, pservers: pservers, contentIdMap: contentIdMap, contents: contentsMap)
    }
    let css = Stylesheet(rules: rules)
    guard let root = rootNode.createElement(with: css) as? SVGSVGElement else {
      return SVGBaseContext(root: nil, pservers: pservers, contentIdMap: contentIdMap, contents: contentsMap)
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

    var context = SVGBaseContext(root: root, pservers: pservers, contentIdMap: contentIdMap, contents: contentsMap)

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

  func parser(_: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
    let name = SVGXmlNameSpace(rawValue: namespaceURI ?? "") == .svg ? (SVGElementName(rawValue: elementName) ?? .unknown) : .unknown
    if !countList.isEmpty {
      countList[countList.count - 1] += 1
    }
    stack.append((name: name, attributes: attributeDict))
    countList.append(1)
  }

  func parser(_: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
    guard let nameSpace = SVGXmlNameSpace(rawValue: namespaceURI) else { return }
    if let value = nameSpaces[prefix] {
      nameSpaces[prefix] = (ns: nameSpace, value.count + 1)
    } else {
      nameSpaces[prefix] = (ns: nameSpace, 1)
    }
  }

  func parser(_: XMLParser, didEndMappingPrefix prefix: String) {
    if let value = nameSpaces[prefix], value.count > 1 {
      nameSpaces[prefix] = (ns: value.ns, count: value.count - 1)
    } else {
      nameSpaces.removeValue(forKey: prefix)
    }
  }

  func parser(_: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
    let name = SVGXmlNameSpace(rawValue: namespaceURI ?? "") == .svg ? (SVGElementName(rawValue: elementName) ?? .unknown) : .unknown
    guard !stack.isEmpty,
      let element = stack.popLast(),
      let count = countList.popLast()
    else { return }
    precondition(name == element.name)
    let attributes = filter(attributes: element.attributes)
    let content: SVGBaseElement? = {
      let contentIds = self.contentIds.shift(count: count)
      var children = [SVGBaseElement]()
      for id in contentIds {
        children.append(contents[id])
      }
      switch element.name {
      case .style:
        let parseInput = ParserInput(input: text)
        let input = Parser(input: parseInput)
        var parser = CSSParser(input: input)
        rules.append(contentsOf: parser.parseRules())
        fallthrough
      case .unknown:
        if !countList.isEmpty {
          countList[countList.count - 1] -= 1
        }
        return nil
      default:
        return SVGBaseElement.create(name: element.name, text: text, attributes: attributes, children: children)
      }
    }()
    self.contentIds = Array(contentIds.dropLast(count - 1))
    text = ""
    guard let content else { return }
    let idx = contents.count
    contents.append(content)
    self.contentIds.append(idx)
  }

  func parser(_: XMLParser, foundCharacters fragment: String) {
    switch stack.last?.name {
    case .text, .style:
      text.append(fragment)
    default:
      break
    }
  }

  func parser(_: XMLParser, parseErrorOccurred parseError: any Error) {
    Self.logger.error("\(parseError.localizedDescription)")
  }
}

extension Array {
  fileprivate func shift(count: Int) -> [Element] {
    Array(dropFirst(self.count - count + 1))
  }
}
