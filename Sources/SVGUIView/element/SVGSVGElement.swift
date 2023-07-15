import UIKit

enum SVGOverflow: String {
    case visible
    case hidden
    case scroll
    case auto
}

struct SVGSVGElement: SVGDrawableElement {
    var type: SVGElementName {
        .svg
    }

    let base: SVGBaseElement
    let preserveAspectRatio: PreserveAspectRatio?
    let overflow: SVGOverflow?
    let x: ElementLength?
    let y: ElementLength?
    let width: SVGLength?
    let height: SVGLength?
    let viewBox: SVGElementRect?
    let contentIds: [Int]

    let font: SVGUIFont?

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case viewBox
        case contentIds
    }

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)

        x = ElementLength(attributes["x"])
        y = ElementLength(attributes["y"])
        width = SVGLength(attributes["width"])
        height = SVGLength(attributes["height"])
        viewBox = Self.parseViewBox(attributes["viewBox"])
        font = Self.parseFont(attributes: attributes)
        preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
        overflow = SVGOverflow(rawValue: attributes["overflow", default: ""].trimmingCharacters(in: .whitespaces))
        self.contentIds = contentIds
    }

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(other: Self, attributes: [String: String]) {
        base = SVGBaseElement(other: other.base, attributes: attributes)

        x = other.x
        y = other.y
        width = .init(attributes["width"]) ?? other.width
        height = .init(attributes["height"]) ?? other.height
        viewBox = other.viewBox
        font = other.font
        contentIds = other.contentIds
        preserveAspectRatio = other.preserveAspectRatio
        overflow = other.overflow
    }

    init(other: SVGSVGElement, index _: Int, css _: SVGUIStyle) {
        self = other
    }

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    private static func parseFont(attributes: [String: String]) -> SVGUIFont? {
        let name = attributes["font-family"]
        let size = Double(attributes["font-size", default: ""]).flatMap { CGFloat($0) }
        let weight = attributes["font-weight"]
        if name == nil, size == nil, weight == nil {
            return nil
        }
        return SVGUIFont(name: name, size: size, weight: weight)
    }

    static func parseViewBox(_ value: String?) -> SVGElementRect? {
        guard let value = value?.trimmingCharacters(in: .whitespaces) else { return nil }
        let nums = value.components(separatedBy: .whitespaces)
        if nums.count == 4,
           let x = Double(nums[0]),
           let y = Double(nums[1]),
           let width = Double(nums[2]),
           let height = Double(nums[3])
        {
            return SVGElementRect(x: x, y: y, width: width, height: height)
        }
        return nil
    }

    func draw(_ context: SVGContext, index _: Int, depth: Int, isRoot: Bool) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        context.saveGState()
        let viewPort = context.viewBox
        let x = (x ?? .pixel(0)).value(total: viewPort.height)
        let y = (y ?? .pixel(0)).value(total: viewPort.width)
        context.concatenate(CGAffineTransform(translationX: x, y: y))
        let height = (height ?? .percent(100)).value(total: viewPort.height)
        let width = (width ?? .percent(100)).value(total: viewPort.width)
        let viewPortSize = CGSize(width: width, height: height)
        let transform = viewBox.map { getTransform(viewBox: $0.toCGRect(), size: viewPortSize) } ?? .identity
        context.concatenate(transform)
        let rect = CGRect(origin: .zero, size: viewPortSize).applying(transform.inverted())
        if let viewBox = viewBox {
            context.push(viewBox: viewBox.toCGRect())
        } else {
            context.push(viewBox: rect)
        }

        let gContext = context.graphics
        let overflow = overflow ?? .hidden
        switch overflow {
        case .visible, .auto:
            break
        default:
            if self.width != nil, self.height != nil {
                gContext.addPath(UIBezierPath(roundedRect: rect, cornerSize: .zero).cgPath)
                gContext.clip()
            }
        }

        gContext.beginTransparencyLayer(auxiliaryInfo: nil)
        font.map {
            context.push(font: $0)
        }
        if isRoot {
            context.pushClipIdStack()
        }
        clipPath?.clipIfNeeded(type: type, frame: context.viewBox, context: context, cgContext: context.graphics)
        for index in contentIds {
            context.contents[index].draw(context, index: index, depth: depth + 1, isRoot: isRoot)
        }
        if isRoot {
            context.popClipIdStack()
        }
        font.map { _ in
            _ = context.popFont()
        }
        context.popViewBox()
        gContext.endTransparencyLayer()
        context.restoreGState()
    }

    func contains(index: Int, context _: SVGContext) -> Bool {
        contentIds.contains(index)
    }

    func clip(context: inout SVGBaseContext) {
        for index in contentIds {
            context.contents[index].clip(context: &context)
        }
    }

    var size: CGSize {
        let rect = viewBox?.toCGRect() ?? .zero
        let width = width ?? .percent(100)
        let height = height ?? .percent(100)
        return CGSize(width: width.value(total: rect.width),
                      height: height.value(total: rect.height))
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        nil
    }
}

extension SVGSVGElement {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encodeIfPresent(viewBox, forKey: .viewBox)
        try container.encode(contentIds, forKey: .contentIds)
    }
}

extension SVGSVGElement {
    func getViewBox(size: CGSize) -> CGRect {
        if let viewBox = viewBox {
            return viewBox.toCGRect()
        }
        let width = width ?? .percent(100)
        let height = height ?? .percent(100)
        return CGRect(x: 0,
                      y: 0,
                      width: width.value(total: size.width),
                      height: height.value(total: size.height))
    }

    func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let preserveAspectRatio = preserveAspectRatio ?? PreserveAspectRatio()
        return preserveAspectRatio.getTransform(viewBox: viewBox, size: size)
    }
}
