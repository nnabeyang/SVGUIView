import Accelerate
import UIKit

struct SVGFilterElement: SVGDrawableElement {
    var base: SVGBaseElement
    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?
    let filterUnits: SVGUnitType?
    let primitiveUnits: SVGUnitType?

    let colorInterpolation: SVGColorInterpolation?
    let colorInterpolationFilters: SVGColorInterpolation?

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
        colorInterpolation = SVGColorInterpolation(rawValue: attributes["color-interpolation", default: ""])
        colorInterpolationFilters = SVGColorInterpolation(rawValue: attributes["color-interpolation-filters", default: ""])
        x = .init(attributes["x"])
        y = .init(attributes["y"])
        width = SVGLength(style: base.style[.width], value: attributes["width"])
        height = SVGLength(style: base.style[.height], value: attributes["height"])
        filterUnits = SVGUnitType(rawValue: attributes["filterUnits", default: ""])
        primitiveUnits = SVGUnitType(rawValue: attributes["primitiveUnits", default: ""])
        self.contentIds = contentIds
    }

    init(other: Self, index _: Int, css _: SVGUIStyle) {
        base = other.base
        colorInterpolation = other.colorInterpolation
        colorInterpolationFilters = other.colorInterpolationFilters
        x = other.x
        y = other.y
        width = other.width
        height = other.height
        filterUnits = other.filterUnits
        primitiveUnits = other.primitiveUnits
        contentIds = other.contentIds
    }

    private func colorSpace(colorInterpolation: SVGColorInterpolation) -> CGColorSpace {
        switch colorInterpolation {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .linearRGB:
            return CGColorSpace(name: CGColorSpace.linearSRGB)!
        }
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        nil
    }

    func filter(content: any SVGDrawableElement, context: SVGContext, cgContext: CGContext) {
        guard !contentIds.isEmpty else { return }
        let bezierPath = content.toBezierPath(context: context)
        let frame = content.frame(context: context, path: bezierPath)
        let effectRect = effectRect(frame: frame, context: context)
        guard let imageCgContext = createImageCGContext(rect: effectRect, colorInterpolation: colorInterpolation ?? .sRGB),
              let srcImage = srcImage(content: content, graphics: imageCgContext, context: context),
              let filterCgContext = createImageCGContext(rect: effectRect, colorInterpolation: colorInterpolationFilters ?? .linearRGB) else { return }
        filterCgContext.saveGState()
        var results = [String: CGImage]()
        var inputImage = srcImage
        var clipRect = effectRect
        for (i, index) in contentIds.enumerated() {
            guard let applier = context.contents[index] as? SVGFilterApplier else { continue }
            filterCgContext.clear(effectRect)
            filterCgContext.restoreGState()
            filterCgContext.saveGState()
            guard let clippedImage = applier.apply(srcImage: srcImage, inImage: inputImage, clipRect: &clipRect,
                                                   filter: self, frame: frame, effectRect: effectRect, opacity: content.opacity,
                                                   cgContext: filterCgContext, context: context, results: results, isFirst: i == 0) else { break }
            if let result = applier.result {
                results[result] = clippedImage
            }
            inputImage = clippedImage
        }
        cgContext.saveGState()
        cgContext.concatenate(content.transform ?? .identity)
        cgContext.draw(inputImage, in: effectRect)
        cgContext.restoreGState()
    }

    private func effectRect(frame: CGRect, context: SVGContext) -> CGRect {
        let filterUnits = filterUnits ?? .objectBoundingBox
        let x = x?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits, isPosition: true) ?? (frame.minX - 0.1 * frame.width)
        let y = y?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits, isPosition: true) ?? (frame.minY - 0.1 * frame.height)
        let width = width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits) ?? 1.2 * frame.width
        let height = height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits) ?? 1.2 * frame.height
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    private func createImageCGContext(rect: CGRect, colorInterpolation: SVGColorInterpolation) -> CGContext? {
        let scale = UIScreen.main.scale
        let frameWidth = Int((rect.width * scale).rounded(.up))
        let frameHeight = Int((rect.height * scale).rounded(.up))
        let bytesPerRow = 4 * frameWidth
        let cgContext = CGContext(data: nil,
                                  width: frameWidth,
                                  height: frameHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace(colorInterpolation: colorInterpolation),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
        cgContext.map {
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: -rect.minX, y: -rect.minY)
            $0.concatenate(transform)
        }
        return cgContext
    }

    private func srcImage(content: any SVGDrawableElement, graphics: CGContext, context: SVGContext) -> CGImage? {
        let nestContext = SVGContext(base: context.base, graphics: graphics, viewPort: context.viewPort)
        nestContext.push(viewBox: context.viewBox)
        graphics.saveGState()
        content.drawWithoutFilter(nestContext, index: 0, depth: 0, mode: .filter(isRoot: true))
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
