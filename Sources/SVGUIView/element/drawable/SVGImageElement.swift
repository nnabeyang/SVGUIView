import UIKit

struct SVGImageElement: SVGDrawableElement {
    var type: SVGElementName {
        .circle
    }

    let base: SVGBaseElement
    let data: Data?
    let x: ElementLength?
    let y: ElementLength?
    let width: ElementLength?
    let height: ElementLength?

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        let src = (attributes["href"] ?? attributes["xlink:href", default: ""]).split(separator: ",").map { String($0) }
        data = src.last.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        x = ElementLength(attributes["x"]) ?? .pixel(0)
        y = ElementLength(attributes["y"]) ?? .pixel(0)
        width = ElementLength(style: base.style[.width], value: attributes["width"])
        height = ElementLength(style: base.style[.height], value: attributes["height"])
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        data = other.data
        x = other.x
        y = other.y
        width = other.width
        height = other.height
    }

    func draw(_ svgContext: SVGContext) {
        let context = svgContext.graphics
        context.saveGState()

        let size = svgContext.viewBox.size
        let x = x?.value(total: size.width) ?? 0
        let y = y?.value(total: size.height) ?? 0
        let width = width?.value(total: size.width) ?? 0
        let height = height?.value(total: size.width) ?? 0
        if let data = data,
           let image = UIImage(data: data),
           let cgImage = image.cgImage
        {
            let s = scale(width: width, height: height, imageSize: image.size)
            let width = image.size.width * s
            let height = image.size.height * s
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: x, y: -height - y, width: width, height: height))
        }
        context.restoreGState()
    }

    private func scale(width: CGFloat, height: CGFloat, imageSize size: CGSize) -> CGFloat {
        let sx = width / size.width
        let sy = height / size.height
        if width == 0 { return sy }
        if height == 0 { return sx }
        return width > height ? sy : sx
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        nil
    }
}

extension SVGImageElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fill, forKey: .fill)
    }
}
