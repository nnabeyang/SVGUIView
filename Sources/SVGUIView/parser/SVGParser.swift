import Foundation
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

final class Parser: NSObject {
    private var pservers: [String: any SVGGradientServer] = [:]
    private var contentIdMap: [String: Int] = [:]
    private var rules: [CSSRule] = []
    private var contents: [SVGElement] = []
    private var contentIds: [Int] = []
    private var countList = [Int]()
    private var stack = [(name: SVGElementName, attributes: [String: String])]()
    private var text: String = ""
    private var nameSpaces = [String: (ns: SVGXmlNameSpace, count: Int)]()

    private static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "parser")

    static func parse(data: Data) -> SVGBaseContext {
        let parser = Parser()
        return parser.parse(data: data)
    }

    private func parse(parser: XMLParser) -> SVGBaseContext {
        parser.delegate = self
        parser.parse()
        let css = CSSStyle(rules: rules)
        contents = contents.enumerated().map { index, element in
            element.style(with: css, at: index)
        }
        var context = SVGBaseContext(pservers: pservers, contentIdMap: contentIdMap, contents: contents)
        contents.last.map {
            $0.clip(context: &context)
            $0.mask(context: &context)
            $0.pattern(context: &context)
            $0.filter(context: &context)
        }
        return context
    }

    private func parse(data: Data) -> SVGBaseContext {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        return parse(parser: parser)
    }
}

extension Parser: XMLParserDelegate {
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
              let count = countList.popLast() else { return }
        precondition(name == element.name)
        let attributes = filter(attributes: element.attributes)
        let content: SVGElement? = {
            let contentIds = self.contentIds.shift(count: count)
            switch element.name {
            case .svg:
                return SVGSVGElement(attributes: attributes, contentIds: contentIds)
            case .g:
                return SVGGroupElement(attributes: attributes, contentIds: contentIds)
            case .clipPath:
                return SVGClipPathElement(attributes: attributes, contentIds: contentIds)
            case .mask:
                return SVGMaskElement(attributes: attributes, contentIds: contentIds)
            case .pattern:
                return SVGPatternElement(attributes: attributes, contentIds: contentIds)
            case .filter:
                return SVGFilterElement(attributes: attributes, contentIds: contentIds)
            case .feMerge:
                return SVGFeMergeElement(attributes: attributes, contentIds: contentIds)
            case .feGaussianBlur:
                return SVGFeGaussianBlurElement(attributes: attributes)
            case .feFlood:
                return SVGFeFloodElement(attributes: attributes)
            case .feBlend:
                return SVGFeBlendElement(attributes: attributes)
            case .feOffset:
                return SVGFeOffsetElement(attributes: attributes)
            case .feMergeNode:
                return SVGFeMergeNodeElement(attributes: attributes)
            case .text:
                return SVGTextElement(text: text, attributes: attributes)
            case .image:
                return SVGImageElement(text: text, attributes: attributes)
            case .line:
                return SVGLineElement(text: text, attributes: attributes)
            case .circle:
                return SVGCircleElement(text: text, attributes: attributes)
            case .ellipse:
                return SVGEllipseElement(text: text, attributes: attributes)
            case .rect:
                return SVGRectElement(text: text, attributes: attributes)
            case .path:
                return SVGPathElement(text: text, attributes: attributes)
            case .polyline:
                return SVGPolylineElement(text: text, attributes: attributes)
            case .polygon:
                return SVGPolygonElement(text: text, attributes: attributes)
            case .stop:
                return SVGStopElement(attributes: attributes)
            case .use:
                return SVGUseElement(attributes: attributes, contentIds: contentIds)
            case .unknown:
                if !countList.isEmpty {
                    countList[countList.count - 1] -= 1
                }
                return nil
            case .defs:
                let element = SVGDefsElement(attributes: attributes, contentIds: contentIds)
                if case .none = (element.display ?? .inline) {
                    for index in element.contentIds {
                        let content = contents[index]
                        switch content {
                        case let content as (any SVGDrawableElement):
                            if let id = content.id {
                                contentIdMap.removeValue(forKey: id)
                            }
                        case let content as (any SVGGradientServer):
                            if let id = content.id {
                                pservers.removeValue(forKey: id)
                            }
                        default:
                            break
                        }
                    }
                }
                return element
            case .linearGradient:
                let pserver = SVGLinearGradientServer(attributes: attributes, contentIds: contentIds)
                if let id = element.attributes["id"], pservers[id] == nil {
                    pservers[id] = pserver
                }
                return pserver
            case .radialGradient:
                let pserver = SVGRadialGradientServer(attributes: attributes, contentIds: contentIds)
                if let id = element.attributes["id"], pservers[id] == nil {
                    pservers[id] = pserver
                }
                return pserver
            case .style:
                text.withUTF8 {
                    let bytes = BufferView(unsafeBufferPointer: $0)!
                    var parser = CSSParser(bytes: bytes)
                    rules.append(contentsOf: parser.parseRules())
                }
                if !countList.isEmpty {
                    countList[countList.count - 1] -= 1
                }
                return nil
            }
        }()
        contentIds = Array(contentIds.dropLast(count - 1))
        text = ""
        content.map {
            let idx = contents.count
            contentIds.append(idx)
            contents.append($0)
            if let id = ($0 as? (any SVGDrawableElement))?.id,
               contentIdMap[id] == nil
            {
                contentIdMap[id] = idx
            }
        }
    }

    func parser(_: XMLParser, foundCharacters fragment: String) {
        switch stack.last?.name {
        case .text, .style:
            text.append(fragment)
        default:
            break
        }
    }

    func parser(_: XMLParser, parseErrorOccurred parseError: Error) {
        Self.logger.error("\(parseError.localizedDescription)")
    }
}

private extension Array {
    func shift(count: Int) -> [Element] {
        Array(dropFirst(self.count - count + 1))
    }
}
