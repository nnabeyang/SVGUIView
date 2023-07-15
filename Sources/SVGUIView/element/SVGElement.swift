import UIKit

protocol SVGElement: Encodable {
    var type: SVGElementName { get }
    func draw(_ context: SVGContext, index: Int, depth: Int, isRoot: Bool)
    func style(with style: CSSStyle, at index: Int) -> any SVGElement
    func contains(index: Int, context: SVGContext) -> Bool
    func clip(context: inout SVGBaseContext)
}

extension SVGElement {
    func contains(index _: Int, context _: SVGContext) -> Bool {
        false
    }

    func clip(context _: inout SVGBaseContext) {}
}

struct SVGBaseElement {
    let id: String?
    let index: Int?
    let opacity: Double
    let eoFill: Bool
    let clipRule: Bool?
    let className: String?
    let transform: CGAffineTransform
    let fill: SVGFill?
    let stroke: SVGUIStroke
    let color: SVGUIColor?
    let clipPath: SVGClipPath?
    let display: CSSDisplay?
    let visibility: CSSVisibility?
    let style: SVGUIStyle

    init(attributes: [String: String]) {
        index = nil
        id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
        className = attributes["class"]?.trimmingCharacters(in: .whitespaces)
        style = SVGUIStyle(description: attributes["style", default: ""])
        color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        clipPath = SVGClipPath(description: attributes["clip-path", default: ""])
        fill = SVGFill(style: style, attributes: attributes)
        stroke = SVGUIStroke(attributes: attributes)
        opacity = Double(attributes["opacity", default: "1"]) ?? 1.0
        transform = CGAffineTransform(style: style[.transform], description: attributes["transform", default: ""])
        eoFill = attributes["fill-rule", default: ""].trimmingCharacters(in: .whitespaces) == "evenodd"
        clipRule = attributes["clip-rule"].map { $0.trimmingCharacters(in: .whitespaces) == "evenodd" }
        display = CSSDisplay(rawValue: attributes["display", default: ""].trimmingCharacters(in: .whitespaces))
        visibility = CSSVisibility(rawValue: attributes["visibility", default: ""].trimmingCharacters(in: .whitespaces))
    }

    init(other: Self, attributes: [String: String]) {
        index = other.index
        id = other.id
        className = other.className
        style = other.style
        color = other.color ?? SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        clipPath = other.clipPath
        fill = SVGFill(lhs: other.fill, rhs: SVGFill(attributes: attributes))
        stroke = SVGUIStroke(lhs: other.stroke, rhs: SVGUIStroke(attributes: attributes))
        opacity = other.opacity * (Double(attributes["opacity", default: "1"]) ?? 1.0)
        transform = other.transform.concatenating(
            CGAffineTransform(description: attributes["transform", default: ""]))
        eoFill = other.eoFill
        clipRule = other.clipRule
        let display = CSSDisplay(rawValue: attributes["display", default: ""].trimmingCharacters(in: .whitespaces))
        self.display = display ?? other.display
        let visibility = CSSVisibility(rawValue: attributes["visibility", default: ""].trimmingCharacters(in: .whitespaces))
        self.visibility = visibility ?? other.visibility
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        self.index = index
        id = other.id
        style = other.style
        className = other.className
        fill = SVGFill(style: css) ?? other.fill
        clipPath = other.clipPath
        color = other.color
        stroke = other.stroke
        opacity = other.opacity
        transform = other.transform
        eoFill = other.eoFill
        clipRule = other.clipRule
        display = other.display
        visibility = other.visibility
    }
}

protocol SVGDrawableElement: SVGElement {
    var id: String? { get }
    var index: Int? { get }
    var base: SVGBaseElement { get }
    var opacity: Double { get }
    var eoFill: Bool { get }
    var clipRule: Bool? { get }
    var className: String? { get }
    var transform: CGAffineTransform { get }
    var fill: SVGFill? { get }
    var stroke: SVGUIStroke { get }
    var color: SVGUIColor? { get }
    var style: SVGUIStyle { get }
    var display: CSSDisplay? { get }
    var visibility: CSSVisibility? { get }
    func frame(context: SVGContext, path: UIBezierPath) -> CGRect
    init(text: String, attributes: [String: String])
    init(base: SVGBaseElement, text: String, attributes: [String: String])
    init(other: Self, index: Int, css: SVGUIStyle)
    init(other: Self, attributes: [String: String])
    func use(attributes: [String: String]) -> Self
    func toBezierPath(context: SVGContext) -> UIBezierPath?
    @available(iOS 16.0, *)
    func toClippedBezierPath(context: SVGContext) -> UIBezierPath?
    func applySVGStroke(stroke: SVGUIStroke, path: UIBezierPath, context: SVGContext)
    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext)
}

extension SVGDrawableElement {
    var id: String? { base.id }
    var index: Int? { base.index }
    var opacity: Double { base.opacity }
    var eoFill: Bool { base.eoFill }
    var clipRule: Bool? { base.clipRule }
    var className: String? { base.className }
    var transform: CGAffineTransform { base.transform }
    var fill: SVGFill? { base.fill }
    var stroke: SVGUIStroke { base.stroke }
    var clipPath: SVGClipPath? { base.clipPath }
    var color: SVGUIColor? { base.color }
    var style: SVGUIStyle { base.style }
    var display: CSSDisplay? { base.display }
    var visibility: CSSVisibility? { base.visibility }

    init(text: String, attributes: [String: String]) {
        let base = SVGBaseElement(attributes: attributes)
        self.init(base: base, text: text, attributes: attributes)
    }

    init(other: Self, attributes: [String: String]) {
        let base = SVGBaseElement(other: other.base, attributes: attributes)
        self.init(base: base, text: "", attributes: attributes)
    }

    func use(attributes: [String: String]) -> Self {
        Self(other: self, attributes: attributes)
    }

    func style(with style: CSSStyle, at index: Int) -> any SVGElement {
        var properties: [CSSValueType: CSSDeclaration] = [:]
        for rule in style.rules.filter({ $0.matches(element: self) }) {
            properties.merge(rule.declarations) { current, _ in current }
        }
        return Self(other: self, index: index, css: SVGUIStyle(decratations: properties))
    }

    func frame(context _: SVGContext, path: UIBezierPath) -> CGRect {
        path.cgPath.boundingBoxOfPath
    }

    @available(iOS 16.0, *)
    func toClippedBezierPath(context: SVGContext) -> UIBezierPath? {
        guard let path = toBezierPath(context: context) else { return nil }
        let frame = frame(context: context, path: path)
        let result: UIBezierPath
        if case let .url(id) = clipPath,
           let clipPath = context.clipPaths[id],
           context.check(clipId: id)
        {
            let bezierPath = clipPath.toBezierPath(context: context, frame: frame)
            context.remove(clipId: id)
            if bezierPath.isEmpty {
                return nil
            }
            let clipRule = clipRule ?? false
            let lcgPath = path.cgPath.normalized(using: clipRule ? .evenOdd : .winding)
            let cgPath = lcgPath.intersection(bezierPath.cgPath)
            result = UIBezierPath(cgPath: cgPath)
        } else {
            result = path
        }
        return result
    }

    func draw(_ context: SVGContext, index _: Int, depth: Int, isRoot: Bool) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        if let display = display, case .none = display {
            return
        }
        context.saveGState()
        context.concatenate(transform)
        if isRoot {
            context.pushTagIdStack()
            context.pushClipIdStack()
        }
        let path: UIBezierPath?
        if #available(iOS 16.0, *), type != .line {
            path = toClippedBezierPath(context: context)
        } else {
            path = toBezierPath(context: context)
            if let path = path {
                let frame = frame(context: context, path: path)
                clipPath?.clipIfNeeded(type: type, frame: frame, context: context, cgContext: context.graphics)
            }
        }
        if isRoot {
            context.popTagIdStack()
            context.popClipIdStack()
        }
        if let path = path {
            applySVGFill(fill: fill, path: path, context: context)
            applySVGStroke(stroke: stroke, path: path, context: context)
        }
        context.restoreGState()
    }

    private func applyStrokeFill(fill: SVGFill, opacity: Double, path: UIBezierPath, context: SVGContext) {
        let cgContext = context.graphics
        switch fill {
        case .inherit:
            if let fill = context.fill {
                applyStrokeFill(fill: fill, opacity: opacity, path: path, context: context)
            }
        case .current:
            if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
                cgContext.setStrokeColor(uiColor.cgColor)
            }
        case let .color(color, colorOpacity):
            let colorOpacity = colorOpacity ?? 1.0
            if let uiColor = color?.toUIColor(opacity: opacity * colorOpacity) {
                cgContext.setStrokeColor(uiColor.cgColor)
            } else {
                cgContext.setStrokeColor(UIColor.clear.cgColor)
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
        let cgContext = context.graphics
        if !dashes.filter({ $0 > 0 }).isEmpty {
            cgContext.setLineDash(phase: offset, lengths: dashes)
        }

        cgContext.addPath(path.cgPath)
        cgContext.setLineWidth(stroke.width ?? 1.0)
        cgContext.setLineCap(stroke.cap ?? .butt)
        cgContext.setLineJoin(stroke.join ?? .miter)
        cgContext.setMiterLimit(stroke.miterLimit ?? 4.0)
        cgContext.drawPath(using: .stroke)
    }

    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext) {
        path.usesEvenOddFillRule = eoFill
        let cgContext = context.graphics
        guard let fill = fill ?? context.fill else {
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            return
        }
        switch fill {
        case .inherit:
            if let fill = context.fill {
                applySVGFill(fill: fill, path: path, context: context)
            } else {
                cgContext.setFillColor(UIColor.black.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            }
        case .current:
            if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
                cgContext.setFillColor(uiColor.cgColor)
            } else {
                cgContext.setFillColor(UIColor.black.cgColor)
            }
            cgContext.addPath(path.cgPath)
            cgContext.drawPath(using: eoFill ? .eoFill : .fill)
        case let .color(color, opacity):
            let opacity = opacity ?? 1.0
            if let uiColor = color?.toUIColor(opacity: self.opacity * opacity) {
                cgContext.setFillColor(uiColor.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            }
        case let .url(id, opacity):
            guard let server = context.pservers[id] else {
                cgContext.setFillColor(UIColor.black.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.drawPath(using: eoFill ? .eoFill : .fill)
                return
            }
            applyPServerFill(server: server, path: path, context: context, opacity: self.opacity * (opacity ?? 1.0))
        }
    }

    func applyPServerFill(server: any SVGGradientServer, path: UIBezierPath, context: SVGContext, opacity: Double) {
        if let id = server.parentId,
           let parent = context.pservers[id],
           let merged = server.merged(other: parent)
        {
            applyPServerFill(server: merged, path: path, context: context, opacity: opacity)
            return
        }
        server.draw(path: path, context: context, opacity: opacity)
    }
}
