import Accelerate
import UIKit

enum SVGColorInterpolation: String {
    case sRGB
    case linearRGB
}

struct SVGMaskElement: SVGDrawableElement {
    var base: SVGBaseElement
    let colorInterpolation: SVGColorInterpolation?
    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?

    var type: SVGElementName {
        .mask
    }

    var transform: CGAffineTransform {
        .identity
    }

    let contentIds: [Int]
    let maskContentUnits: SVGUnitType?

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)
        colorInterpolation = SVGColorInterpolation(rawValue: attributes["color-interpolation", default: ""])
        x = .init(attributes["x"])
        y = .init(attributes["y"])
        width = SVGLength(style: base.style[.width], value: attributes["width"])
        height = SVGLength(style: base.style[.height], value: attributes["height"])
        maskContentUnits = SVGUnitType(rawValue: attributes["maskContentUnits", default: ""])
        self.contentIds = contentIds
    }

    init(other: Self, index _: Int, css _: SVGUIStyle) {
        base = other.base
        colorInterpolation = other.colorInterpolation
        x = other.x
        y = other.y
        width = other.width
        height = other.height
        maskContentUnits = other.maskContentUnits
        contentIds = other.contentIds
    }

    var colorSpace: CGColorSpace {
        let colorIntepolation = colorInterpolation ?? .sRGB
        switch colorIntepolation {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .linearRGB:
            return CGColorSpace(name: CGColorSpace.linearSRGB)!
        }
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        fatalError()
    }

    func clip(frame: CGRect, context: SVGContext, cgContext: CGContext) async -> Bool {
        guard let maskImage = await maskImage(frame: frame, context: context) else { return false }
        let x = (x ?? .percent(-10)).value(context: context, mode: .width)
        let y = (y ?? .percent(-10)).value(context: context, mode: .height)
        let width = (width ?? .percent(120)).value(context: context, mode: .width)
        let height = (height ?? .percent(120)).value(context: context, mode: .height)
        cgContext.clip(to: CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height)))
        cgContext.clip(to: frame, mask: maskImage)
        return true
    }

    private func maskImage(frame: CGRect, context: SVGContext) async -> CGImage? {
        let size = frame.size
        let scale = await UIScreen.main.scale
        let frameWidth = Int((size.width * scale).rounded(.up))
        let frameHeight = Int((size.height * scale).rounded(.up))
        let bytesPerRow = 4 * frameWidth
        guard let graphics = CGContext(data: nil,
                                       width: frameWidth,
                                       height: frameHeight,
                                       bitsPerComponent: 8,
                                       bytesPerRow: bytesPerRow,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
        else {
            return nil
        }

        let transform: CGAffineTransform
        let maskContentUnits = maskContentUnits ?? .userSpaceOnUse
        let t = self.transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        switch maskContentUnits {
        case .userSpaceOnUse:
            transform = t
                .translatedBy(x: -frame.minX, y: -frame.minY)
        case .objectBoundingBox:
            transform = t
                .scaledBy(x: size.width, y: size.height)
        }

        let maskContext = SVGContext(base: context.base, graphics: graphics, viewPort: context.viewPort)
        maskContext.push(viewBox: context.viewBox)
        graphics.concatenate(transform)
        for index in contentIds {
            guard let content = context.contents[index] as? (any SVGDrawableElement) else { continue }
            if content is SVGGroupElement ||
                content is SVGLineElement
            {
                continue
            }
            if case .hidden = content.visibility {
                continue
            }
            if let display = content.display, case .none = display {
                continue
            }
            content.font.map {
                context.push(font: $0)
            }
            guard let bezierPath = await content.toBezierPath(context: context) else { continue }
            content.font.map { _ in
                _ = context.popFont()
            }
            graphics.saveGState()
            graphics.concatenate(content.transform ?? .identity)
            await content.clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: graphics)
            await content.mask?.clipIfNeeded(frame: frame, context: context, cgContext: graphics)
            await content.applySVGFill(fill: content.fill, path: bezierPath, context: maskContext, mode: .root)
            graphics.restoreGState()
        }
        await clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: graphics)
        guard let image = graphics.makeImage() else { return nil }
        graphics.restoreGState()
        return convertToLuminance(cgImage: image)
    }

    func convertToLuminance(cgImage: CGImage) -> CGImage? {
        guard let sourceBuffer = try? vImage_Buffer(cgImage: cgImage) else {
            return nil
        }
        defer {
            sourceBuffer.free()
        }
        guard let format = vImage_CGImageFormat(bitsPerComponent: cgImage.bitsPerComponent,
                                                bitsPerPixel: cgImage.bitsPerPixel,
                                                colorSpace: cgImage.colorSpace!,
                                                bitmapInfo: cgImage.bitmapInfo)
        else {
            return nil
        }

        let srcPtr = sourceBuffer.data.assumingMemoryBound(to: Pixel_8.self)
        let width = sourceBuffer.width
        let height = sourceBuffer.height
        let pixelSize = width * height * 4
        var pixelOffset = 0
        while pixelOffset < pixelSize {
            let a = srcPtr[pixelOffset + 3]
            if a == 0 {
                pixelOffset += 4
                continue
            }
            let b = srcPtr[pixelOffset]
            let g = srcPtr[pixelOffset + 1]
            let r = srcPtr[pixelOffset + 2]

            let luma = (Double(r) * 0.2125 + Double(g) * 0.7154 + Double(b) * 0.0721)
            srcPtr[pixelOffset + 3] = Pixel_8(luma)
            pixelOffset += 4
        }
        return try? sourceBuffer.createCGImage(format: format)
    }

    func draw(_: SVGContext, index _: Int, mode _: DrawMode) async {}

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    func mask(context: inout SVGBaseContext) {
        if let id = id, context.masks[id] == nil {
            context.setMask(id: id, value: self)
        }
    }
}

extension SVGMaskElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case d
        case fill
    }

    func encode(to _: any Encoder) throws {
        fatalError()
    }
}
