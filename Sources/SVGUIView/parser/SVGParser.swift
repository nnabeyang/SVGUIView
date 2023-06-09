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
}

final class Parser: NSObject {
    private var pservers: [String: SVGGradientServer] = [:]
    private var rules: [CSSRule] = []
    private var contents: [SVGElement] = []
    private var countList = [Int]()
    private var stack = [(name: SVGElementName, attributes: [String: String])]()
    private var text: String = ""
    private static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "parser")
    var root: SVGSVGElement? {
        guard let element = stack.first, case .svg = element.name else { return nil }
        let svg = SVGSVGElement(attributes: element.attributes, contents: contents)
        let css = CSSStyle(rules: rules)
        return svg.style(with: css) as? SVGSVGElement
    }

    static func parse(contentsOf url: URL) -> (SVGSVGElement, SVGPaintServer)? {
        let parser = Parser()
        return parser.parse(contentsOf: url)
    }

    private func parse(contentsOf url: URL) -> (SVGSVGElement, SVGPaintServer)? {
        guard let parser = XMLParser(contentsOf: url) else {
            return nil
        }
        parser.delegate = self
        parser.parse()
        guard let root = root else { return nil }
        return (root, pserver: SVGPaintServer(servers: pservers))
    }
}

extension Parser: XMLParserDelegate {
    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        guard let name = SVGElementName(rawValue: elementName) else { return }
        if !countList.isEmpty {
            countList[countList.count - 1] += 1
        }
        stack.append((name: name, attributes: attributeDict))
        countList.append(1)
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        guard let name = SVGElementName(rawValue: elementName) else { return }
        guard stack.count > 1,
              let element = stack.popLast(),
              let count = countList.popLast() else { return }
        precondition(name == element.name)
        let content: SVGElement? = {
            switch element.name {
            case .svg:
                let element = SVGSVGElement(attributes: element.attributes,
                                            contents: Array(contents.dropFirst(contents.count - count + 1)))
                contents = Array(contents.dropLast(count - 1))
                return element
            case .g:
                let element = SVGGroupElement(attributes: element.attributes,
                                              contents: Array(contents.dropFirst(contents.count - count + 1)))
                contents = Array(contents.dropLast(count - 1))
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
            case .linearGradient:
                let pserver = SVGLinearGradientServer(attributes: element.attributes,
                                                      contents: Array(contents.dropFirst(contents.count - count + 1)))
                contents = Array(contents.dropLast(count - 1))
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
                contents = Array(contents.dropLast(count - 1))
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
                return nil
            }
        }()
        text = ""
        content.map {
            contents.append($0)
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
