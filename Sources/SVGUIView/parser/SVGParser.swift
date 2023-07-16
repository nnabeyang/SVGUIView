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
    case unknown
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
        }
        return context
    }

    private func parse(data: Data) -> SVGBaseContext {
        parse(parser: XMLParser(data: data))
    }
}

extension Parser: XMLParserDelegate {
    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        let name = SVGElementName(rawValue: elementName) ?? .unknown
        if !countList.isEmpty {
            countList[countList.count - 1] += 1
        }
        stack.append((name: name, attributes: attributeDict))
        countList.append(1)
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        let name = SVGElementName(rawValue: elementName) ?? .unknown
        guard !stack.isEmpty,
              let element = stack.popLast(),
              let count = countList.popLast() else { return }
        precondition(name == element.name)
        let content: SVGElement? = {
            switch element.name {
            case .svg:
                let element = SVGSVGElement(attributes: element.attributes,
                                            contentIds: Array(contentIds.dropFirst(contentIds.count - count + 1)))
                return element
            case .g:
                let element = SVGGroupElement(attributes: element.attributes,
                                              contentIds: Array(contentIds.dropFirst(contentIds.count - count + 1)))
                return element
            case .clipPath:
                let element = SVGClipPathElement(attributes: element.attributes,
                                                 contentIds: Array(contentIds.dropFirst(contentIds.count - count + 1)))
                return element
            case .mask:
                let element = SVGMaskElement(attributes: element.attributes,
                                             contentIds: Array(contentIds.dropFirst(contentIds.count - count + 1)))
                return element
            case .text:
                return SVGTextElement(text: text, attributes: element.attributes)
            case .image:
                return SVGImageElement(text: text, attributes: element.attributes)
            case .line:
                return SVGLineElement(text: text, attributes: element.attributes)
            case .circle:
                return SVGCircleElement(text: text, attributes: element.attributes)
            case .ellipse:
                return SVGEllipseElement(text: text, attributes: element.attributes)
            case .rect:
                return SVGRectElement(text: text, attributes: element.attributes)
            case .path:
                return SVGPathElement(text: text, attributes: element.attributes)
            case .polyline:
                return SVGPolylineElement(text: text, attributes: element.attributes)
            case .polygon:
                return SVGPolygonElement(text: text, attributes: element.attributes)
            case .stop:
                return SVGStopElement(attributes: element.attributes)
            case .use:
                return SVGUseElement(attributes: element.attributes, contentIds: Array(contentIds.dropFirst(contentIds.count - count + 1)))
            case .unknown:
                if !countList.isEmpty {
                    countList[countList.count - 1] -= 1
                }
                return nil
            case .defs:
                let element = SVGDefsElement(attributes: element.attributes,
                                             contentIds: Array(contentIds.dropFirst(contentIds.count - count + 1)))
                return element
            case .linearGradient:
                let pserver = SVGLinearGradientServer(attributes: element.attributes,
                                                      contents: Array(contents.dropFirst(contents.count - count + 1)))
                if let id = element.attributes["id"], pservers[id] == nil {
                    pservers[id] = pserver
                }
                if !countList.isEmpty {
                    countList[countList.count - 1] -= 1
                }
                return nil
            case .radialGradient:
                let pserver = SVGRadialGradientServer(attributes: element.attributes,
                                                      contents: Array(contents.dropFirst(contents.count - count + 1)))
                if let id = element.attributes["id"], pservers[id] == nil {
                    pservers[id] = pserver
                }
                if !countList.isEmpty {
                    countList[countList.count - 1] -= 1
                }
                return nil
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
