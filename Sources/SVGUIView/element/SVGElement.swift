import UIKit

protocol SVGElement: Encodable {
    var type: SVGElementName { get }
    func draw(_ context: SVGContext)
    func style(with style: CSSStyle) -> any SVGElement
}

struct SVGBaseElement {
    let id: String?
    let opacity: Double
    let eoFill: Bool
    let className: String?
    let transform: CGAffineTransform
    let fill: SVGFill?
    let stroke: SVGUIStroke
    let color: SVGUIColor?
    let style: SVGUIStyle

    init(attributes: [String: String]) {
        id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
        className = attributes["class"]?.trimmingCharacters(in: .whitespaces)
        style = SVGUIStyle(description: attributes["style", default: ""])
        color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        fill = SVGFill(style: style, attributes: attributes)
        stroke = SVGUIStroke(attributes: attributes)
        opacity = Double(attributes["opacity", default: "1"]) ?? 1.0
        transform = CGAffineTransform(style: style[.transform], description: attributes["transform", default: ""])
        eoFill = attributes["fill-rule", default: ""].trimmingCharacters(in: .whitespaces) == "evenodd"
    }

    init(other: Self, css: SVGUIStyle) {
        id = other.id
        style = other.style
        className = other.className
        fill = SVGFill(style: css) ?? other.fill
        color = other.color
        stroke = other.stroke
        opacity = other.opacity
        transform = other.transform
        eoFill = other.eoFill
    }
}

protocol SVGDrawableElement: SVGElement {
    var id: String? { get }
    var base: SVGBaseElement { get }
    var opacity: Double { get }
    var eoFill: Bool { get }
    var className: String? { get }
    var transform: CGAffineTransform { get }
    var fill: SVGFill? { get }
    var stroke: SVGUIStroke { get }
    var color: SVGUIColor? { get }
    var style: SVGUIStyle { get }
    init(text: String, attributes: [String: String])
    init(base: SVGBaseElement, text: String, attributes: [String: String])
    init(other: Self, css: SVGUIStyle)
    func draw(_ context: SVGContext)
    func toBezierPath(context: SVGContext) -> UIBezierPath?
    func applySVGStroke(stroke: SVGUIStroke, path: UIBezierPath, context: SVGContext)
    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext)
}

extension SVGDrawableElement {
    var id: String? { base.id }
    var opacity: Double { base.opacity }
    var eoFill: Bool { base.eoFill }
    var className: String? { base.className }
    var transform: CGAffineTransform { base.transform }
    var fill: SVGFill? { base.fill }
    var stroke: SVGUIStroke { base.stroke }
    var color: SVGUIColor? { base.color }
    var style: SVGUIStyle { base.style }

    init(text: String, attributes: [String: String]) {
        let base = SVGBaseElement(attributes: attributes)
        self.init(base: base, text: text, attributes: attributes)
    }

    func style(with style: CSSStyle) -> any SVGElement {
        var properties: [CSSValueType: CSSDeclaration] = [:]
        for rule in style.rules.filter({ $0.matches(element: self) }) {
            properties.merge(rule.declarations) { current, _ in current }
        }
        return Self(other: self, css: SVGUIStyle(decratations: properties))
    }

    func draw(_ context: SVGContext) {
        context.saveGState()
        guard let path = toBezierPath(context: context) else { return }
        context.concatenate(transform)
        applySVGFill(fill: fill, path: path, context: context)
        applySVGStroke(stroke: stroke, path: path, context: context)
        context.restoreGState()
    }

    private func applyStrokeFill(fill: SVGFill, opacity: Double, path: UIBezierPath, context: SVGContext) {
        switch fill {
        case .inherit:
            if let fill = context.fill {
                applyStrokeFill(fill: fill, opacity: opacity, path: path, context: context)
            }
        case .current:
            if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
                uiColor.setStroke()
            }
        case let .color(color, colorOpacity):
            let colorOpacity = colorOpacity ?? 1.0
            if let uiColor = color?.toUIColor(opacity: opacity * colorOpacity) {
                uiColor.setStroke()
            } else {
                UIColor.clear.setStroke()
            }
        case .url:
            fatalError()
        }
    }

    func applySVGStroke(stroke elementStroke: SVGUIStroke, path: UIBezierPath, context: SVGContext) {
        let stroke = SVGUIStroke(lhs: elementStroke, rhs: context.stroke)
        guard let fill = stroke.fill else { return }
        let dashes = stroke.dashes ?? []
        let offset = stroke.offset ?? 0
        applyStrokeFill(fill: fill, opacity: opacity * (stroke.opacity ?? 1.0), path: path, context: context)
        if !dashes.filter({ $0 > 0 }).isEmpty {
            path.setLineDash(dashes, count: dashes.count, phase: offset)
        }
        path.lineWidth = stroke.width ?? 1.0
        path.lineCapStyle = stroke.cap ?? .butt
        path.lineJoinStyle = stroke.join ?? .miter
        path.miterLimit = stroke.miterLimit ?? 4.0
        path.stroke()
    }

    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext) {
        path.usesEvenOddFillRule = eoFill
        guard let fill = fill ?? context.fill else {
            UIColor.black.setFill()
            path.fill()
            return
        }
        switch fill {
        case .inherit:
            if let fill = context.fill {
                applySVGFill(fill: fill, path: path, context: context)
            } else {
                UIColor.black.setFill()
                path.fill()
            }
        case .current:
            if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
                uiColor.setFill()
                path.fill()
            } else {
                UIColor.black.setFill()
                path.fill()
            }
        case let .color(color, opacity):
            let opacity = opacity ?? 1.0
            if let uiColor = color?.toUIColor(opacity: self.opacity * opacity) {
                uiColor.setFill()
                path.fill()
            }
        case let .url(id, opacity):
            guard let server = context.pserver.servers[id] else {
                UIColor.black.setFill()
                path.fill()
                return
            }
            applyPServerFill(server: server, path: path, context: context, opacity: self.opacity * (opacity ?? 1.0))
        }
    }

    func applyPServerFill(server: any SVGGradientServer, path: UIBezierPath, context: SVGContext, opacity: Double) {
        if let id = server.parentId,
           let parent = context.pserver.servers[id],
           let merged = server.merged(other: parent)
        {
            applyPServerFill(server: merged, path: path, context: context, opacity: opacity)
            return
        }
        server.draw(path: path, context: context)
    }
}
