import UIKit

struct SVGImageElement: SVGDrawableElement {
    var type: SVGElementName {
        .circle
    }

    let base: SVGBaseElement
    let data: Data?
    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        let src = (attributes["href"] ?? attributes["xlink:href", default: ""]).split(separator: ",").map { String($0) }
        data = src.last.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        x = SVGLength(attributes["x"]) ?? .pixel(0)
        y = SVGLength(attributes["y"]) ?? .pixel(0)
        width = SVGLength(style: base.style[.width], value: attributes["width"])
        height = SVGLength(style: base.style[.height], value: attributes["height"])
    }

    init(other: Self, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        data = other.data
        x = other.x
        y = other.y
        width = other.width
        height = other.height
    }

    func draw(_ context: SVGContext, index _: Int, depth: Int, mode _: DrawMode) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        let cgContext = context.graphics
        context.saveGState()
        let x = x?.value(context: context, mode: .width) ?? 0
        let y = y?.value(context: context, mode: .width) ?? 0
        let width = width?.value(context: context, mode: .width) ?? 0
        let height = height?.value(context: context, mode: .height) ?? 0
        if let data = data,
           let image = UIImage(data: data),
           let cgImage = image.cgImage
        {
            let s = scale(width: width, height: height, imageSize: image.size)
            let width = image.size.width * s
            let height = image.size.height * s
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.draw(cgImage, in: CGRect(x: x, y: -height - y, width: width, height: height))
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
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fill, forKey: .fill)
    }
}
