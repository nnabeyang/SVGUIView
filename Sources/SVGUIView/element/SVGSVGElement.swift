import Foundation

struct SVGSVGElement: SVGElement {
    var type: SVGElementName {
        .svg
    }

    let width: ElementLength
    let height: ElementLength
    let viewBox: SVGElementRect?
    let contents: [SVGElement]
    let font: SVGUIFont?

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case viewBox
        case contents
    }

    init(attributes: [String: String], contents: [SVGElement & Encodable]) {
        width = .init(attributes["width"]) ?? .percent(100)
        height = .init(attributes["height"]) ?? .percent(100)
        viewBox = Self.parseViewBox(attributes["viewBox"])
        font = Self.parseFont(attributes: attributes)
        self.contents = contents
    }

    init(other: Self, css: CSSStyle) {
        width = other.width
        height = other.height
        viewBox = other.viewBox
        font = other.font
        contents = other.contents.map { $0.style(with: css) }
    }

    func style(with css: CSSStyle) -> any SVGElement {
        SVGSVGElement(other: self, css: css)
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

    func draw(_ context: SVGContext) {
        context.saveGState()
        context.concatenate(context.transform)
        let gcontext = context.graphics
        gcontext.beginTransparencyLayer(auxiliaryInfo: nil)
        font.map {
            context.push(font: $0)
        }
        for node in contents {
            node.draw(context)
        }
        font.map { _ in
            _ = context.popFont()
        }
        gcontext.endTransparencyLayer()
        context.restoreGState()
    }

    var size: CGSize {
        let rect = viewBox?.toCGRect() ?? .zero
        return CGSize(width: width.value(total: rect.width),
                      height: height.value(total: rect.height))
    }
}

extension SVGSVGElement {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encodeIfPresent(viewBox, forKey: .viewBox)
        var contentsContainer = container.nestedUnkeyedContainer(forKey: .contents)
        for content in contents {
            try contentsContainer.encode(content)
        }
    }
}

extension SVGSVGElement {
    func getViewBox(size: CGSize) -> CGRect {
        if let viewBox = viewBox {
            return viewBox.toCGRect()
        }

        return CGRect(x: 0,
                      y: 0,
                      width: width.value(total: size.width),
                      height: height.value(total: size.height))
    }

    func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: viewBox.size)

        let widthRatio = size.width / rect.width
        let heightRatio = size.height / rect.height

        let newSize: CGSize
        if heightRatio < widthRatio {
            newSize = CGSize(width: rect.width * heightRatio, height: size.height)
        } else {
            newSize = CGSize(width: size.width, height: rect.height * widthRatio)
        }
        let sx = newSize.width / rect.width
        let sy = newSize.height / rect.height
        let dx = (size.width - newSize.width) / (2 * sx) - viewBox.minX
        let dy = (size.height - newSize.height) / (2 * sy) - viewBox.minY
        return CGAffineTransform(scaleX: sx, y: sy).translatedBy(x: dx, y: dy)
    }
}
