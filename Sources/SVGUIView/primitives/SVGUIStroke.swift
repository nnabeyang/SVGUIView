import CoreGraphics

private enum LineCapType: String {
    case butt
    case round
    case square
    case inherit
}

private enum JoinType: String {
    case miter
    case round
    case bevel
}

struct SVGUIStroke {
    let fill: SVGFill?
    let opacity: CGFloat?
    let width: SVGLength?
    let cap: CGLineCap?
    let join: CGLineJoin?
    let miterLimit: CGFloat?
    let dashes: [CGFloat]?
    let offset: CGFloat?
    init(fill: SVGFill?, opacity: CGFloat?, width: SVGLength?, cap: CGLineCap?, join: CGLineJoin?, miterLimit: CGFloat?, dashes: [CGFloat]?, offset: CGFloat?) {
        self.fill = fill
        self.opacity = opacity
        self.width = width
        self.cap = cap
        self.join = join
        self.miterLimit = miterLimit
        self.dashes = dashes
        self.offset = offset
    }

    init(attributes: [String: String]) {
        fill = SVGFill(description: attributes["stroke", default: ""])
        opacity = Self.parseNumber(description: attributes["stroke-opacity", default: ""])
        width = SVGLength(attributes["stroke-width", default: ""])
        cap = Self.getCap(attribute: attributes["stroke-linecap", default: ""])
        join = Self.getStrokeJoin(attribute: attributes["stroke-linejoin", default: ""])
        miterLimit = Self.parseNumber(description: attributes["stroke-miterlimit", default: ""])
        dashes = Self.parseDashes(description: attributes["stroke-dasharray", default: ""])
        offset = Self.parseNumber(description: attributes["stroke-dashoffset", default: ""])
    }

    init(lhs: SVGUIStroke, rhs: SVGUIStroke?) {
        guard let rhs = rhs else {
            self = lhs
            return
        }
        fill = lhs.fill ?? rhs.fill
        opacity = lhs.opacity ?? rhs.opacity
        width = lhs.width ?? rhs.width
        cap = lhs.cap ?? rhs.cap
        join = lhs.join ?? rhs.join
        miterLimit = lhs.miterLimit ?? rhs.miterLimit
        dashes = lhs.dashes ?? rhs.dashes
        offset = lhs.offset ?? rhs.offset
    }

    private static func getCap(attribute: String) -> CGLineCap? {
        guard let type = LineCapType(rawValue: attribute.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        switch type {
        case .butt:
            return .butt
        case .round:
            return .round
        case .square:
            return .square
        case .inherit:
            return .butt
        }
    }

    private static func getStrokeJoin(attribute: String) -> CGLineJoin? {
        guard let type = JoinType(rawValue: attribute.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        switch type {
        case .miter:
            return .miter
        case .round:
            return .round
        case .bevel:
            return .bevel
        }
    }

    private static func parseDashes(description: String) -> [CGFloat]? {
        var data = description
        let dashes = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanDashes()
        }
        return dashes.isEmpty ? nil : dashes
    }

    private static func parseNumber(description: String) -> CGFloat? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanNumber().flatMap { CGFloat($0) }
        }
    }
}
