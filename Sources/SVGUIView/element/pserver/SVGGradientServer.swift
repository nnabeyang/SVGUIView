import CoreGraphics
import UIKit

enum SpreadMethod: String {
    case pad
}

protocol SVGGradientServer {
    var parentId: String? { get }
    func merged(other: SVGGradientServer) -> (any SVGGradientServer)?
    func draw(path: UIBezierPath, context: SVGContext)
}

struct SVGLinearGradientServer: SVGGradientServer {
    let color: SVGUIColor?
    let stops: [SVGStopElement]?
    let link: String?
    let userSpace: Bool?
    let spreadMethod: SpreadMethod?
    let x1: CGFloat?
    let y1: CGFloat?
    let x2: CGFloat?
    let y2: CGFloat?

    private enum CodingKeys: String, CodingKey {
        case stops
    }

    init(attributes: [String: String], contents: [SVGElement & Encodable]) {
        x1 = Double(attributes["x1", default: ""]).flatMap { CGFloat($0) }
        y1 = Double(attributes["y1", default: ""]).flatMap { CGFloat($0) }
        x2 = Double(attributes["x2", default: ""]).flatMap { CGFloat($0) }
        y2 = Double(attributes["y2", default: ""]).flatMap { CGFloat($0) }
        color = Self.parseColor(description: attributes["color", default: ""])
        let stops = contents.compactMap { $0 as? SVGStopElement }
        self.stops = stops.isEmpty ? nil : stops
        link = Self.parseLink(description: attributes["xlink:href"])
        userSpace = attributes["gradientUnits"].flatMap { $0 == "userSpaceOnUse" }
        spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""]) ?? .pad
    }

    func merged(other: SVGGradientServer) -> SVGGradientServer? {
        guard let other = other as? SVGLinearGradientServer else { return nil }
        return Self(lhs: self, rhs: other)
    }

    init(lhs: SVGLinearGradientServer, rhs: SVGLinearGradientServer) {
        x1 = lhs.x1 ?? rhs.x1
        y1 = lhs.y1 ?? rhs.y1
        x2 = lhs.x2 ?? rhs.x2
        y2 = lhs.y2 ?? rhs.y2
        color = lhs.color ?? rhs.color
        stops = lhs.stops ?? rhs.stops
        link = rhs.link
        userSpace = lhs.userSpace ?? rhs.userSpace
        spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    }

    private static func parseLink(description: String?) -> String? {
        guard let description = description else { return nil }
        let hashId = description.trimmingCharacters(in: .whitespaces)
        if hashId.hasPrefix("#") {
            return String(hashId.dropFirst())
        }
        return nil
    }

    private static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGColorScanner(bytes: bytes)
            return scanner.scanColor()
        }
    }

    private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
        SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
    }

    var parentId: String? {
        guard stops?.isEmpty ?? true else { return nil }
        return link
    }

    func draw(path: UIBezierPath, context: SVGContext) {
        let stops = stops ?? []
        let userSpace = userSpace ?? false
        let x1 = x1 ?? 0
        let y1 = y1 ?? 0
        let x2 = x2 ?? 1
        let y2 = y2 ?? 0
        let spreadMethod = spreadMethod ?? .pad

        let colors = stops.compactMap {
            switch $0.color {
            case .current:
                return color?.toUIColor(opacity: 1.0)?.cgColor
            case let .color(color, _):
                return color.toUIColor(opacity: 1.0)?.cgColor
            default:
                fatalError("not implemented")
            }
        }
        guard !colors.isEmpty else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let locations: [CGFloat] = stops.map(\.offset.value)
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
        let gContext = context.graphics
        gContext.saveGState()
        gContext.addPath(path.cgPath)
        gContext.clip()
        let frame = path.cgPath.boundingBoxOfPath
        let (sx, sy): (CGFloat, CGFloat) = {
            if userSpace {
                return (1.0, 1.0)
            }
            if x1 == x2 || y1 == y2 {
                return (frame.width, frame.height)
            }
            let s = min(frame.width, frame.height)
            return (s, s)
        }()
        let rect = CGRect(x: x1 * sx, y: y1 * sy, width: (x2 - x1) * sx, height: (y2 - y1) * sy)
        let rx = userSpace ? 1.0 : sx / frame.width
        let ry = userSpace ? 1.0 : sy / frame.height
        let _x1 = rect.minX
        let _y1 = rect.minY
        let _x2 = rect.maxX
        let _y2 = rect.maxY
        let x = frame.minX * rx
        let y = frame.minY * ry

        let start = CGPoint(x: x + _x1, y: y + _y1)
        let end = CGPoint(x: x + _x2, y: y + _y2)
        if sx == sy {
            gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
        }
        let options: CGGradientDrawingOptions
        switch spreadMethod {
        case .pad:
            options = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        }
        gContext.drawLinearGradient(gradient, start: start, end: end, options: options)
        gContext.restoreGState()
    }
}

extension SVGLinearGradientServer {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        var contentsContainer = container.nestedUnkeyedContainer(forKey: .stops)
        for content in stops ?? [] {
            try contentsContainer.encode(content)
        }
    }
}

struct SVGRadialGradientServer: SVGGradientServer {
    let color: SVGUIColor?
    let stops: [SVGStopElement]?
    let spreadMethod: SpreadMethod?
    let userSpace: Bool?
    let link: String?

    let cx: CGFloat?
    let cy: CGFloat?
    let fx: CGFloat?
    let fy: CGFloat?
    let r: CGFloat?

    private enum CodingKeys: String, CodingKey {
        case stops
    }

    init(attributes: [String: String], contents: [SVGElement & Encodable]) {
        color = Self.parseColor(description: attributes["color", default: ""])
        cx = Double(attributes["cx", default: ""]).flatMap { CGFloat($0) }
        cy = Double(attributes["cy", default: ""]).flatMap { CGFloat($0) }
        fx = Double(attributes["fx", default: ""]).flatMap { CGFloat($0) }
        fy = Double(attributes["fy", default: ""]).flatMap { CGFloat($0) }
        r = Double(attributes["r", default: ""]).flatMap { CGFloat($0) }

        let stops = contents.compactMap { $0 as? SVGStopElement }
        self.stops = stops.isEmpty ? nil : stops
        spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])
        link = Self.parseLink(description: attributes["xlink:href"])
        userSpace = attributes["gradientUnits"].flatMap { $0 == "userSpaceOnUse" }
    }

    func merged(other: SVGGradientServer) -> SVGGradientServer? {
        guard let other = other as? Self else { return nil }
        return Self(lhs: self, rhs: other)
    }

    init(lhs: SVGRadialGradientServer, rhs: SVGRadialGradientServer) {
        color = lhs.color ?? rhs.color
        cx = lhs.cx ?? rhs.cx
        cy = lhs.cy ?? rhs.cy
        fx = lhs.fx ?? rhs.fx
        fy = lhs.fy ?? rhs.fy
        r = lhs.r ?? rhs.r
        stops = lhs.stops ?? rhs.stops
        spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
        link = rhs.link
        userSpace = lhs.userSpace ?? rhs.userSpace
    }

    private static func parseLink(description: String?) -> String? {
        guard let description = description else { return nil }
        let hashId = description.trimmingCharacters(in: .whitespaces)
        if hashId.hasPrefix("#") {
            return String(hashId.dropFirst())
        }
        return nil
    }

    private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
        SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
    }

    private static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGColorScanner(bytes: bytes)
            return scanner.scanColor()
        }
    }

    var parentId: String? {
        guard stops?.isEmpty ?? true else { return nil }
        return link
    }

    func draw(path: UIBezierPath, context: SVGContext) {
        let stops = stops ?? []
        let userSpace = userSpace ?? false
        let spreadMethod = spreadMethod ?? .pad
        let cx = cx ?? 0.5
        let cy = cy ?? 0.5
        let r = r ?? 0.5

        let colors = stops.compactMap {
            switch $0.color {
            case .current:
                return color?.toUIColor(opacity: 1.0)?.cgColor
            case let .color(color, _):
                return color.toUIColor(opacity: 1.0)?.cgColor
            default:
                fatalError("not implemented")
            }
        }
        guard !colors.isEmpty else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let locations: [CGFloat] = stops.map(\.offset.value)

        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!

        let gContext = context.graphics
        gContext.saveGState()
        gContext.addPath(path.cgPath)
        gContext.clip()
        let frame = path.cgPath.boundingBoxOfPath
        let pp = CGPoint(x: cx, y: cy)

        let s = userSpace ? 1.0 : min(frame.width, frame.height)
        let rx = userSpace ? 1.0 : s / frame.width
        let ry = userSpace ? 1.0 : s / frame.height
        let _cx = (pp.x * s + (userSpace ? 0 : frame.minX * rx))
        let _cy = (pp.y * s + (userSpace ? 0 : frame.minY * ry))
        let _r = r * s

        if !userSpace, frame.width != frame.height {
            gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
        }
        let options: CGGradientDrawingOptions
        switch spreadMethod {
        case .pad:
            options = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        }
        gContext.drawRadialGradient(gradient,
                                    startCenter: .init(x: _cx, y: _cy),
                                    startRadius: 0,
                                    endCenter: .init(x: _cx, y: _cy),
                                    endRadius: _r,
                                    options: options)
        context.restoreGState()
    }
}

extension SVGRadialGradientServer {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        var contentsContainer = container.nestedUnkeyedContainer(forKey: .stops)
        for content in stops ?? [] {
            try contentsContainer.encode(content)
        }
    }
}