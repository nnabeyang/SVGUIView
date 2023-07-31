import CoreGraphics
import UIKit

enum SpreadMethod: String {
    case pad
    case `repeat`
    case reflect
}

protocol SVGGradientServer {
    var parentId: String? { get }
    func merged(other: any SVGGradientServer) -> (any SVGGradientServer)?
    func draw(path: UIBezierPath, context: SVGContext, opacity: Double)
    init(lhs: Self, rhs: SVGLinearGradientServer)
    init(lhs: Self, rhs: SVGRadialGradientServer)
}

extension SVGGradientServer {
    func merged(other: any SVGGradientServer) -> (any SVGGradientServer)? {
        switch other {
        case let other as SVGLinearGradientServer:
            return Self(lhs: self, rhs: other)
        case let other as SVGRadialGradientServer:
            return Self(lhs: self, rhs: other)
        default:
            fatalError("not implemented")
        }
    }
}

struct SVGLinearGradientServer: SVGGradientServer {
    let color: SVGUIColor?
    let stops: [SVGStopElement]?
    let parentId: String?
    let userSpace: Bool?
    let spreadMethod: SpreadMethod?
    let x1: SVGLength?
    let y1: SVGLength?
    let x2: SVGLength?
    let y2: SVGLength?

    private enum CodingKeys: String, CodingKey {
        case stops
    }

    init(attributes: [String: String], contents: [SVGElement & Encodable]) {
        x1 = SVGLength(attributes["x1"])
        y1 = SVGLength(attributes["y1"])
        x2 = SVGLength(attributes["x2"])
        y2 = SVGLength(attributes["y2"])
        color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        let stops = contents.compactMap { $0 as? SVGStopElement }
        self.stops = stops.isEmpty ? nil : stops
        parentId = Self.parseLink(description: attributes["xlink:href"])
        userSpace = attributes["gradientUnits"].flatMap { $0 == "userSpaceOnUse" }
        spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])
    }

    init(lhs: Self, rhs: SVGLinearGradientServer) {
        x1 = lhs.x1 ?? rhs.x1
        y1 = lhs.y1 ?? rhs.y1
        x2 = lhs.x2 ?? rhs.x2
        y2 = lhs.y2 ?? rhs.y2
        color = lhs.color ?? rhs.color
        stops = lhs.stops ?? rhs.stops
        parentId = rhs.parentId
        userSpace = lhs.userSpace ?? rhs.userSpace
        spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    }

    init(lhs: Self, rhs: SVGRadialGradientServer) {
        x1 = lhs.x1
        y1 = lhs.y1
        x2 = lhs.x2
        y2 = lhs.y2
        color = lhs.color ?? rhs.color
        stops = lhs.stops ?? rhs.stops
        parentId = rhs.parentId
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

    private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
        SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
    }

    func draw(path: UIBezierPath, context: SVGContext, opacity: Double) {
        let stops = stops ?? []
        let userSpace = userSpace ?? false
        let x1 = (x1 ?? .percent(0)).value(context: context, mode: .width, userSpace: userSpace)
        let y1 = (y1 ?? .percent(0)).value(context: context, mode: .height, userSpace: userSpace)
        let x2 = (x2 ?? .percent(100)).value(context: context, mode: .width, userSpace: userSpace)
        let y2 = (y2 ?? .percent(0)).value(context: context, mode: .height, userSpace: userSpace)
        let spreadMethod = spreadMethod ?? .pad

        let colors = stops.compactMap {
            switch $0.color {
            case .current:
                return color?.toUIColor(opacity: $0.opacity * opacity)?.cgColor
            case let .color(color, colorOpacity):
                let colorOpacity = colorOpacity ?? 1.0
                return color?.toUIColor(opacity: $0.opacity * opacity * colorOpacity)?.cgColor
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
        let x = userSpace ? 0 : frame.minX * rx
        let y = userSpace ? 0 : frame.minY * ry

        if sx == sy {
            gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
        }

        switch spreadMethod {
        case .pad:
            let start = CGPoint(x: x + _x1, y: y + _y1)
            let end = CGPoint(x: x + _x2, y: y + _y2)
            let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            gContext.drawLinearGradient(gradient, start: start, end: end, options: options)
        case .repeat:
            let dx = _x2 - _x1
            let dy = _y2 - _y1
            let n = min(ceil((x + _x1 - frame.minX) / dx), ceil((y + _y1 - frame.minY) / dy))
            let base = CGPoint(x: x + _x1 - dx * n, y: y + _y1 - dy * n)
            let m = min(ceil((frame.maxX - base.x) / dx), ceil((frame.maxY - base.y) / dy))
            for i in stride(from: 0, to: m, by: 1) {
                let start = CGPoint(x: base.x + i * dx, y: base.y + i * dy)
                let end = CGPoint(x: base.x + (i + 1) * dx, y: base.y + (i + 1) * dy)
                gContext.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
        case .reflect:
            let reflected = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations.reversed())!
            let dx = _x2 - _x1
            let dy = _y2 - _y1
            let n = min(ceil((x + _x1 - frame.minX) / dx), ceil((y + _y1 - frame.minY) / dy))
            let base = CGPoint(x: x + _x1 - dx * n, y: y + _y1 - dy * n)
            let m = min(ceil((frame.maxX - base.x) / dx), ceil((frame.maxY - base.y) / dy))
            for i in stride(from: 0, to: m, by: 1) {
                let start = CGPoint(x: base.x + i * dx, y: base.y + i * dy)
                let end = CGPoint(x: base.x + (i + 1) * dx, y: base.y + (i + 1) * dy)
                if Int(i - n) % 2 == 0 {
                    gContext.drawLinearGradient(gradient, start: start, end: end, options: [])
                } else {
                    gContext.drawLinearGradient(reflected, start: start, end: end, options: [])
                }
            }
        }
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
    let parentId: String?
    let cx: SVGLength?
    let cy: SVGLength?
    let fx: SVGLength?
    let fy: SVGLength?
    let r: SVGLength?

    private enum CodingKeys: String, CodingKey {
        case stops
    }

    init(attributes: [String: String], contents: [SVGElement & Encodable]) {
        color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        cx = SVGLength(attributes["cx"])
        cy = SVGLength(attributes["cy"])
        fx = SVGLength(attributes["fx"])
        fy = SVGLength(attributes["fy"])
        r = SVGLength(attributes["r"])

        let stops = contents.compactMap { $0 as? SVGStopElement }
        self.stops = stops.isEmpty ? nil : stops
        spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])
        parentId = Self.parseLink(description: attributes["xlink:href"])
        userSpace = attributes["gradientUnits"].flatMap { $0 == "userSpaceOnUse" }
    }

    init(lhs: Self, rhs: SVGRadialGradientServer) {
        color = lhs.color ?? rhs.color
        cx = lhs.cx ?? rhs.cx
        cy = lhs.cy ?? rhs.cy
        fx = lhs.fx ?? rhs.fx
        fy = lhs.fy ?? rhs.fy
        r = lhs.r ?? rhs.r
        stops = lhs.stops ?? rhs.stops
        spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
        parentId = rhs.parentId
        userSpace = lhs.userSpace ?? rhs.userSpace
    }

    init(lhs: Self, rhs: SVGLinearGradientServer) {
        color = lhs.color ?? rhs.color
        cx = lhs.cx
        cy = lhs.cy
        fx = lhs.fx
        fy = lhs.fy
        r = lhs.r
        stops = lhs.stops ?? rhs.stops
        spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
        parentId = rhs.parentId
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

    func draw(path: UIBezierPath, context: SVGContext, opacity: Double) {
        let stops = stops ?? []
        let userSpace = userSpace ?? false
        let cx = (cx ?? .percent(50)).value(context: context, mode: .width, userSpace: userSpace)
        let cy = (cy ?? .percent(50)).value(context: context, mode: .width, userSpace: userSpace)
        let r = (r ?? .percent(50)).value(context: context, mode: .height, userSpace: userSpace)
        let colors = stops.compactMap {
            switch $0.color {
            case .current:
                return color?.toUIColor(opacity: opacity)?.cgColor
            case let .color(color, colorOpacity):
                let colorOpacity = colorOpacity ?? 1.0
                return color?.toUIColor(opacity: $0.opacity * opacity * colorOpacity)?.cgColor
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
        gContext.drawRadialGradient(gradient,
                                    startCenter: .init(x: _cx, y: _cy),
                                    startRadius: 0,
                                    endCenter: .init(x: _cx, y: _cy),
                                    endRadius: _r,
                                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
