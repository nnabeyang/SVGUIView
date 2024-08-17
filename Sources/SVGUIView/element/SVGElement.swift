import UIKit

protocol SVGElement: Encodable {
    var type: SVGElementName { get }
    func draw(_ context: SVGContext, index: Int, depth: Int, mode: DrawMode)
    func drawWithoutFilter(_ context: SVGContext, index: Int, depth: Int, mode: DrawMode)
    func style(with style: CSSStyle, at index: Int) -> any SVGElement
    func contains(index: Int, context: SVGContext) -> Bool
    func clip(context: inout SVGBaseContext)
    func mask(context: inout SVGBaseContext)
    func pattern(context: inout SVGBaseContext)
    func filter(context: inout SVGBaseContext)
}

extension SVGElement {
    func contains(index _: Int, context _: SVGContext) -> Bool {
        false
    }

    func clip(context _: inout SVGBaseContext) {}
    func mask(context _: inout SVGBaseContext) {}
    func pattern(context _: inout SVGBaseContext) {}
    func filter(context _: inout SVGBaseContext) {}
}

enum WritingMode: String {
    case horizontalTB = "horizontal-tb"
    case verticalRL = "vertical-rl"
    case verticalLR = "vertical-lr"
}

enum DrawMode: Equatable {
    case normal
    case root
    case filter(isRoot: Bool)
}

struct SVGBaseElement {
    let id: String?
    let index: Int?
    let opacity: Double
    let eoFill: Bool
    let clipRule: Bool?
    let className: String?
    let transform: CGAffineTransform?
    let font: SVGUIFont?
    let fill: SVGFill?
    let stroke: SVGUIStroke
    let color: SVGUIColor?
    let clipPath: SVGClipPath?
    let mask: SVGMask?
    let filter: SVGFilter?
    let display: CSSDisplay?
    let visibility: CSSVisibility?
    let writingMode: WritingMode?
    let style: SVGUIStyle

    init(attributes: [String: String]) {
        index = nil
        id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
        className = attributes["class"]?.trimmingCharacters(in: .whitespaces)
        style = SVGUIStyle(description: attributes["style", default: ""])
        color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
        clipPath = SVGClipPath(description: attributes["clip-path", default: ""])
        mask = SVGMask(description: attributes["mask", default: ""])
        filter = SVGFilter(description: attributes["filter", default: ""])
        font = Self.parseFont(attributes: attributes)
        fill = SVGFill(style: style, attributes: attributes)
        stroke = SVGUIStroke(attributes: attributes)
        opacity = Double(attributes["opacity", default: "1"]) ?? 1.0
        transform = CGAffineTransform(style: style[.transform], description: attributes["transform", default: ""])
        writingMode = WritingMode(rawValue: attributes["writing-mode", default: ""])
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
        mask = other.mask
        filter = other.filter ?? SVGFilter(description: attributes["filter", default: ""])
        font = other.font.flatMap { SVGUIFont(lhs: $0, rhs: Self.parseFont(attributes: attributes)) } ?? Self.parseFont(attributes: attributes)
        fill = SVGFill(lhs: other.fill, rhs: SVGFill(attributes: attributes))
        stroke = SVGUIStroke(lhs: other.stroke, rhs: SVGUIStroke(attributes: attributes))
        opacity = other.opacity * (Double(attributes["opacity", default: "1"]) ?? 1.0)

        let transform = CGAffineTransform(description: attributes["transform", default: ""])
            .flatMap { other.transform?.concatenating($0) ?? $0 } ??
            other.transform
        self.transform = transform
        writingMode = other.writingMode
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
        font = other.font
        fill = SVGFill(style: css) ?? other.fill
        clipPath = other.clipPath
        mask = other.mask
        filter = other.filter
        color = other.color
        stroke = other.stroke
        opacity = other.opacity
        transform = CGAffineTransform(style: css[.transform]) ?? other.transform
        writingMode = other.writingMode
        eoFill = other.eoFill
        clipRule = other.clipRule
        display = other.display
        visibility = other.visibility
    }

    private static func parseFont(attributes: [String: String]) -> SVGUIFont? {
        let name = attributes["font-family"]?.trimmingCharacters(in: .whitespaces)
        let size = attributes["font-size"]?.trimmingCharacters(in: .whitespaces)
        let weight = attributes["font-weight"]?.trimmingCharacters(in: .whitespaces)
        if name == nil,
           size == nil,
           weight == nil
        {
            return nil
        }
        return SVGUIFont(name: name, size: size, weight: weight)
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
    var transform: CGAffineTransform? { get }
    var writingMode: WritingMode? { get }
    var font: SVGUIFont? { get }
    var fill: SVGFill? { get }
    var stroke: SVGUIStroke { get }
    var color: SVGUIColor? { get }
    var style: SVGUIStyle { get }
    var display: CSSDisplay? { get }
    var visibility: CSSVisibility? { get }
    func frame(context: SVGContext, path: UIBezierPath?) -> CGRect
    func scale(context: SVGContext) -> CGAffineTransform
    init(text: String, attributes: [String: String])
    init(base: SVGBaseElement, text: String, attributes: [String: String])
    init(other: Self, index: Int, css: SVGUIStyle)
    init(other: Self, attributes: [String: String])
    func use(attributes: [String: String]) -> Self
    func toBezierPath(context: SVGContext) -> UIBezierPath?
    func toClippedBezierPath(context: SVGContext) -> UIBezierPath?
    func applySVGStroke(stroke: SVGUIStroke, path: UIBezierPath, context: SVGContext)
    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext, mode: DrawMode)
}

extension SVGDrawableElement {
    var id: String? { base.id }
    var index: Int? { base.index }
    var opacity: Double { base.opacity }
    var eoFill: Bool { base.eoFill }
    var clipRule: Bool? { base.clipRule }
    var className: String? { base.className }
    var transform: CGAffineTransform? { base.transform }
    var writingMode: WritingMode? { base.writingMode }
    var font: SVGUIFont? { base.font }
    var fill: SVGFill? { base.fill }
    var stroke: SVGUIStroke { base.stroke }
    var clipPath: SVGClipPath? { base.clipPath }
    var mask: SVGMask? { base.mask }
    var filter: SVGFilter? { base.filter }
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

    func frame(context _: SVGContext, path: UIBezierPath?) -> CGRect {
        path?.cgPath.boundingBoxOfPath ?? .zero
    }

    func scale(context: SVGContext) -> CGAffineTransform {
        let contentUnit = context.patternContentUnit ?? .userSpaceOnUse
        switch contentUnit {
        case .userSpaceOnUse:
            return .identity
        case .objectBoundingBox:
            let size = context.viewBox.size
            return CGAffineTransform(scaleX: size.width, y: size.height)
        }
    }

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

    func drawWithoutFilter(_ context: SVGContext, index _: Int, depth _: Int, mode: DrawMode) {
        context.saveGState()
        if mode != .filter(isRoot: true) {
            context.concatenate(transform ?? .identity)
        }
        writingMode.map {
            context.push(writingMode: $0)
        }
        font.map {
            context.push(font: $0)
        }
        switch mode {
        case .root, .filter:
            context.pushTagIdStack()
            context.pushClipIdStack()
            context.pushMaskIdStack()
            context.pushPatternIdStack()
        default:
            break
        }
        let path: UIBezierPath?
        if type != .line {
            path = toClippedBezierPath(context: context)
            if let path = toBezierPath(context: context) {
                let frame = frame(context: context, path: path)
                mask?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
            }
        } else {
            path = toBezierPath(context: context)
            if let path = path {
                let frame = frame(context: context, path: path)
                clipPath?.clipIfNeeded(type: type, frame: frame, context: context, cgContext: context.graphics)
                let lineWidth = stroke.width?.value(context: context, mode: .other)

                if mask != nil, type == .line, frame.width == lineWidth || frame.height == lineWidth {
                    context.graphics.clip(to: .zero)
                } else {
                    mask?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
                }
            }
        }
        let gContext = context.graphics
        gContext.setAlpha(opacity)
        gContext.beginTransparencyLayer(auxiliaryInfo: nil)
        if let path = path {
            applySVGFill(fill: fill, path: path, context: context, mode: mode)
            applySVGStroke(stroke: stroke, path: path, context: context)
        }
        switch mode {
        case .root, .filter:
            context.popTagIdStack()
            context.popClipIdStack()
            context.popMaskIdStack()
            context.popPatternIdStack()
        default:
            break
        }
        writingMode.map { _ in
            _ = context.popWritingMode()
        }
        font.map { _ in
            _ = context.popFont()
        }
        gContext.endTransparencyLayer()
        context.restoreGState()
    }

    func draw(_ context: SVGContext, index: Int, depth: Int, mode: DrawMode) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        if let display = display, case .none = display {
            return
        }
        let filter = filter ?? SVGFilter.none
        if case let .url(id) = filter,
           let server = context.filters[id]
        {
            server.filter(content: self, context: context, cgContext: context.graphics)
            return
        }
        drawWithoutFilter(context, index: index, depth: depth, mode: mode)
    }

    func drawWithoutFilter(_ context: SVGContext, index _: Int, mode: DrawMode) async {
        context.saveGState()
        if mode != .filter(isRoot: true) {
            context.concatenate(transform ?? .identity)
        }
        writingMode.map {
            context.push(writingMode: $0)
        }
        font.map {
            context.push(font: $0)
        }
        switch mode {
        case .root, .filter:
            context.pushTagIdStack()
            context.pushClipIdStack()
            context.pushMaskIdStack()
            context.pushPatternIdStack()
        default:
            break
        }
        let path: UIBezierPath?
        if type != .line {
            path = toClippedBezierPath(context: context)
            if let path = toBezierPath(context: context) {
                let frame = frame(context: context, path: path)
                mask?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
            }
        } else {
            path = toBezierPath(context: context)
            if let path = path {
                let frame = frame(context: context, path: path)
                clipPath?.clipIfNeeded(type: type, frame: frame, context: context, cgContext: context.graphics)
                let lineWidth = stroke.width?.value(context: context, mode: .other)

                if mask != nil, type == .line, frame.width == lineWidth || frame.height == lineWidth {
                    context.graphics.clip(to: .zero)
                } else {
                    mask?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
                }
            }
        }
        let gContext = context.graphics
        gContext.setAlpha(opacity)
        gContext.beginTransparencyLayer(auxiliaryInfo: nil)
        if let path = path {
            applySVGFill(fill: fill, path: path, context: context, mode: mode)
            applySVGStroke(stroke: stroke, path: path, context: context)
        }
        switch mode {
        case .root, .filter:
            context.popTagIdStack()
            context.popClipIdStack()
            context.popMaskIdStack()
            context.popPatternIdStack()
        default:
            break
        }
        writingMode.map { _ in
            _ = context.popWritingMode()
        }
        font.map { _ in
            _ = context.popFont()
        }
        gContext.endTransparencyLayer()
        context.restoreGState()
    }

    func draw(_ context: SVGContext, index: Int, mode: DrawMode) async {
        if Task.isCancelled { return }
        if let display = display, case .none = display {
            return
        }
        let filter = filter ?? SVGFilter.none
        if case let .url(id) = filter,
           let server = context.filters[id]
        {
            server.filter(content: self, context: context, cgContext: context.graphics)
            return
        }
        await drawWithoutFilter(context, index: index, mode: mode)
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
            let colorOpacity = colorOpacity?.value ?? 1.0
            if let uiColor = color?.toUIColor(opacity: opacity * colorOpacity) {
                cgContext.setStrokeColor(uiColor.cgColor)
            } else {
                cgContext.setStrokeColor(UIColor.clear.cgColor)
            }
        case .url:
            // TODO: implement url color case
            break
        }
    }

    func applySVGStroke(stroke elementStroke: SVGUIStroke, path: UIBezierPath, context: SVGContext) {
        let stroke = SVGUIStroke(lhs: elementStroke, rhs: context.stroke)
        guard let fill = stroke.fill else { return }
        let dashes = stroke.dashes ?? []
        let offset = stroke.offset ?? 0
        applyStrokeFill(fill: fill, opacity: stroke.opacity ?? 1.0, path: path, context: context)
        let cgContext = context.graphics
        if !dashes.filter({ $0 > 0 }).isEmpty {
            cgContext.setLineDash(phase: offset, lengths: dashes)
        }
        let lineWidth = stroke.width?.value(context: context, mode: .other) ?? 1.0
        cgContext.addPath(path.cgPath)
        cgContext.setLineWidth(lineWidth)
        cgContext.setLineCap(stroke.cap ?? .butt)
        cgContext.setLineJoin(stroke.join ?? .miter)
        cgContext.setMiterLimit(stroke.miterLimit ?? 4.0)
        cgContext.drawPath(using: .stroke)
    }

    func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext, mode: DrawMode) {
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
                if case .inherit = fill {
                    let fill = context.popFill()
                    if let fill = context.fill {
                        applySVGFill(fill: fill, path: path, context: context, mode: mode)
                    }
                    fill.map {
                        context.push(fill: $0)
                    }
                } else {
                    applySVGFill(fill: fill, path: path, context: context, mode: mode)
                }
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
            let opacity = opacity?.value ?? 1.0
            if let uiColor = color?.toUIColor(opacity: opacity) {
                cgContext.setFillColor(uiColor.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.drawPath(using: eoFill ? .eoFill : .fill)
            }
        case let .url(id, opacity):
            if let server = context.pservers[id] {
                switch server.display ?? .inline {
                case .none:
                    break
                default:
                    applyPServerFill(server: server, path: path, context: context, opacity: opacity?.value ?? 1.0)
                    return
                }
            } else if let pattern = context.patterns[id],
                      context.check(patternId: id)
            {
                let frame = frame(context: context, path: path)
                let cgContext = context.graphics
                let opacity = opacity?.value ?? 1.0
                cgContext.saveGState()
                cgContext.setAlpha(opacity)
                cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
                _ = pattern.pattern(path: path, frame: frame, context: context, cgContext: cgContext, mode: mode)
                cgContext.endTransparencyLayer()
                cgContext.restoreGState()
                context.remove(patternId: id)
                return
            }
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.drawPath(using: eoFill ? .eoFill : .fill)
        }
    }

    func applyPServerFill(server: any SVGGradientServer, path: UIBezierPath, context: SVGContext, opacity: CGFloat) {
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
