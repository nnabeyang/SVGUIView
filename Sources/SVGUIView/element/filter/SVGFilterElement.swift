import Accelerate
import UIKit

enum SVGPrimitiveUnitsType: String {
    case userSpaceOnUse
    case objectBoundingBox
}

struct SVGFilterElement: SVGDrawableElement {
    var base: SVGBaseElement
    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?
    let userSpace: Bool?
    let primitiveUnits: SVGPrimitiveUnitsType?

    var type: SVGElementName {
        .filter
    }

    var transform: CGAffineTransform {
        .identity
    }

    let contentIds: [Int]

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)
        x = .init(attributes["x"])
        y = .init(attributes["y"])
        width = SVGLength(style: base.style[.width], value: attributes["width"])
        height = SVGLength(style: base.style[.height], value: attributes["height"])
        userSpace = attributes["filterUnits"].flatMap { $0 == "userSpaceOnUse" }
        primitiveUnits = SVGPrimitiveUnitsType(rawValue: attributes["primitiveUnits", default: ""])
        self.contentIds = contentIds
    }

    init(other: Self, index _: Int, css _: SVGUIStyle) {
        base = other.base
        x = other.x
        y = other.y
        width = other.width
        height = other.height
        userSpace = other.userSpace
        primitiveUnits = other.primitiveUnits
        contentIds = other.contentIds
    }

    var colorSpace: CGColorSpace {
        CGColorSpaceCreateDeviceRGB()
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        nil
    }

    func filter(content: any SVGDrawableElement, index: Int, context: SVGContext, cgContext: CGContext) {
        guard let bezierPath = content.toBezierPath(context: context) else { return }
        let frame = content.frame(context: context, path: bezierPath)
        let effectRect = effectRect(frame: frame, context: context)
        guard let imageCgContext = createImageCGContext(rect: effectRect) else { return }
        guard var srcImage = srcImage(content: content, index: index, graphics: imageCgContext, context: context) else { return }
        guard var format = vImage_CGImageFormat(bitsPerComponent: srcImage.bitsPerComponent,
                                                bitsPerPixel: srcImage.bitsPerPixel,
                                                colorSpace: srcImage.colorSpace!,
                                                bitmapInfo: srcImage.bitmapInfo)
        else {
            return
        }

        for index in contentIds {
            guard var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format),
                  var destBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
            else { break }
            guard let applier = context.contents[index] as? SVGFilterApplier else { continue }
            applier.apply(srcBuffer: &srcBuffer, destBuffer: &destBuffer, context: context)
            guard let image = vImageCreateCGImageFromBuffer(&destBuffer,
                                                            &format,
                                                            { _, _ in },
                                                            nil,
                                                            vImage_Flags(kvImageNoAllocate),
                                                            nil)?.takeRetainedValue() else { break }
            let rect = applier.frame(filter: self, frame: frame, context: context)
            imageCgContext.clear(effectRect)
            imageCgContext.saveGState()
            imageCgContext.setAlpha(content.opacity)
            imageCgContext.clip(to: rect)
            imageCgContext.draw(image, in: effectRect)
            guard let clippedImage = imageCgContext.makeImage() else { break }
            imageCgContext.restoreGState()
            srcImage = clippedImage
        }
        cgContext.saveGState()
        let transform = CGAffineTransform(translationX: effectRect.minX, y: effectRect.minY)
            .concatenating(content.transform)
            .translatedBy(x: -effectRect.minX, y: -effectRect.minY)
        cgContext.concatenate(transform)
        cgContext.draw(srcImage, in: effectRect)
        cgContext.restoreGState()
    }

    private func effectRect(frame: CGRect, context: SVGContext) -> CGRect {
        let userSpace = userSpace ?? false
        let dx = x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: userSpace) ?? -0.1 * frame.width
        let dy = y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace) ?? -0.1 * frame.height
        let x = userSpace ? dx : frame.minX + dx
        let y = userSpace ? dy : frame.minY + dy
        let width = width?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: userSpace) ?? 1.2 * frame.width
        let height = height?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace) ?? 1.2 * frame.height
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    private func createImageCGContext(rect: CGRect) -> CGContext? {
        let scale = UIScreen.main.scale
        let frameWidth = Int((rect.width * scale).rounded(.up))
        let frameHeight = Int((rect.height * scale).rounded(.up))
        let bytesPerRow = 4 * frameWidth
        let cgContext = CGContext(data: nil,
                                  width: frameWidth,
                                  height: frameHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)

        cgContext.map {
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: -rect.minX, y: -rect.minY)
            $0.concatenate(transform)
        }
        return cgContext
    }

    private func srcImage(content: any SVGDrawableElement, index: Int, graphics: CGContext, context: SVGContext) -> CGImage? {
        let nestContext = SVGContext(base: context.base, graphics: graphics, viewPort: context.viewPort)
        nestContext.push(viewBox: context.viewBox)
        graphics.saveGState()
        content.draw(nestContext, index: index, depth: 0, mode: .filter)
        guard let image = graphics.makeImage() else { return nil }
        graphics.restoreGState()
        return image
    }

    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {}

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    func filter(context: inout SVGBaseContext) {
        if let id = id, context.filters[id] == nil {
            context.setFilter(id: id, value: self)
        }
    }
}

extension SVGFilterElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case d
        case fill
    }

    func encode(to _: Encoder) throws {
        fatalError()
    }
}

private extension CGImage {
    static func fromvImageOutBuffer(_ outBuffer: vImage_Buffer) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue & CGBitmapInfo.alphaInfoMask.rawValue

        let context = CGContext(data: outBuffer.data,
                                width: Int(outBuffer.width),
                                height: Int(outBuffer.height),
                                bitsPerComponent: 8,
                                bytesPerRow: outBuffer.rowBytes,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo)!

        return context.makeImage()
    }
}
