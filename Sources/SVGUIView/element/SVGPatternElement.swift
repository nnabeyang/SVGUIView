import Accelerate
import UIKit

enum SVGPatternContentUnitsType: String {
    case userSpaceOnUse
    case objectBoundingBox
}

struct SVGPatternElement: SVGDrawableElement {
    var base: SVGBaseElement
    let colorInterpolation: SVGColorInterpolation?
    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?
    let patternContentUnits: SVGPatternContentUnitsType?
    let patternTransform: CGAffineTransform?
    let preserveAspectRatio: PreserveAspectRatio?
    let viewBox: SVGElementRect?
    let parentId: String?

    var type: SVGElementName {
        .pattern
    }

    var transform: CGAffineTransform {
        .identity
    }

    let contentIds: [Int]
    let userSpace: Bool?

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)
        colorInterpolation = SVGColorInterpolation(rawValue: attributes["color-interpolation", default: ""])
        x = SVGLength(attributes["x"])
        y = SVGLength(attributes["y"])
        width = SVGLength(style: base.style[.width], value: attributes["width"])
        height = SVGLength(style: base.style[.height], value: attributes["height"])

        patternTransform = CGAffineTransform(description: attributes["patternTransform", default: ""])
        userSpace = attributes["patternUnits"].flatMap { $0 == "userSpaceOnUse" }
        patternContentUnits = SVGPatternContentUnitsType(rawValue: attributes["patternContentUnits", default: ""])
        preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
        viewBox = Self.parseViewBox(attributes["viewBox"])
        parentId = Self.parseLink(description: attributes["href"] ?? attributes["xlink:href"])

        self.contentIds = contentIds
    }

    init(other: Self, index _: Int, css _: SVGUIStyle) {
        base = other.base
        colorInterpolation = other.colorInterpolation
        x = other.x
        y = other.y
        width = other.width
        height = other.height
        patternTransform = other.patternTransform
        userSpace = other.userSpace
        patternContentUnits = other.patternContentUnits
        preserveAspectRatio = other.preserveAspectRatio
        viewBox = other.viewBox
        parentId = other.parentId
        contentIds = other.contentIds
    }

    init(lhs: Self, rhs: Self) {
        base = rhs.base
        colorInterpolation = lhs.colorInterpolation ?? rhs.colorInterpolation
        x = lhs.x ?? rhs.x
        y = lhs.y ?? rhs.y
        width = lhs.width ?? rhs.width
        height = lhs.height ?? rhs.height
        patternTransform = lhs.patternTransform ?? rhs.patternTransform
        userSpace = lhs.userSpace ?? rhs.userSpace
        patternContentUnits = lhs.patternContentUnits ?? rhs.patternContentUnits
        preserveAspectRatio = lhs.preserveAspectRatio ?? rhs.preserveAspectRatio
        viewBox = lhs.viewBox ?? rhs.viewBox
        parentId = rhs.parentId
        if !rhs.contentIds.isEmpty {
            contentIds = rhs.contentIds
        } else {
            contentIds = lhs.contentIds
        }
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

    private static func parseLink(description: String?) -> String? {
        guard let description = description else { return nil }
        let hashId = description.trimmingCharacters(in: .whitespaces)
        if hashId.hasPrefix("#") {
            return String(hashId.dropFirst())
        }
        return nil
    }

    func size(frame: CGRect, context: SVGContext) -> CGSize {
        let userSpace = userSpace ?? false
        let width = width?.value(context: context, mode: .width, userSpace: userSpace) ?? 0
        let height = height?.value(context: context, mode: .height, userSpace: userSpace) ?? 0
        return userSpace ? CGSize(width: width, height: height) : CGSize(width: width * frame.width, height: height * frame.height)
    }

    func pattern(path: UIBezierPath, frame: CGRect, context: SVGContext, cgContext: CGContext, isRoot: Bool) -> Bool {
        if let parentId = parentId,
           let parent = context.patterns[parentId],
           context.check(patternId: parentId)
        {
            let pattern = SVGPatternElement(lhs: self, rhs: parent)
            let result = pattern.pattern(path: path, frame: frame, context: context, cgContext: cgContext, isRoot: false)
            context.remove(patternId: parentId)
            return result
        }
        guard let tileImage = tileImage(frame: frame, context: context, isRoot: isRoot) else { return false }
        let drawPattern: CGPatternDrawPatternCallback = { info, context in
            guard let info = info else { return }
            let image = Unmanaged<CGImage>.fromOpaque(info).takeUnretainedValue()
            let size = CGSize(width: image.width, height: image.height)
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        let releaseInfo: CGPatternReleaseInfoCallback = { info in
            guard let info = info else { return }
            Unmanaged<CGImage>.fromOpaque(info).release()
        }
        var callbacks = CGPatternCallbacks(
            version: 0,
            drawPattern: drawPattern, releaseInfo: releaseInfo
        )
        let x: CGFloat
        let y: CGFloat
        let userSpace = userSpace ?? false
        if userSpace {
            x = self.x?.value(context: context, mode: .width) ?? 0
            y = self.y?.value(context: context, mode: .height) ?? 0
        } else {
            x = (self.x?.value(context: context, mode: .width, userSpace: userSpace) ?? 0) * frame.width + frame.minX
            y = (self.y?.value(context: context, mode: .height, userSpace: userSpace) ?? 0) * frame.height + frame.minY
        }
        let imageSize = size(frame: frame, context: context).applying((patternTransform ?? .identity).scale)
        let scaleX = (imageSize.width * UIScreen.main.scale) / CGFloat(tileImage.width)
        let scaleY = (imageSize.height * UIScreen.main.scale) / CGFloat(tileImage.height)
        let transform = (patternTransform ?? .identity).withoutScaling
        guard let pattern = CGPattern(
            info: Unmanaged.passRetained(tileImage).toOpaque(),
            bounds: CGRect(origin: .zero, size: frame.size),
            matrix: transform
                .concatenating(context.transform.translatedBy(x: x * UIScreen.main.scale, y: y * UIScreen.main.scale)
                    .scaledBy(x: scaleX, y: scaleY)),
            xStep: CGFloat(tileImage.width),
            yStep: CGFloat(tileImage.height),
            tiling: .constantSpacing,
            isColored: true,
            callbacks: &callbacks
        ) else { return false }
        var alpha: CGFloat = 1
        guard let patternSpace = CGColorSpace(patternBaseSpace: nil) else { return false }

        cgContext.addPath(path.cgPath)
        cgContext.setFillColorSpace(patternSpace)
        cgContext.setFillPattern(pattern, colorComponents: &alpha)
        cgContext.drawPath(using: .fill)
        return true
    }

    private func tileImage(frame: CGRect, context: SVGContext, isRoot: Bool) -> CGImage? {
        let transform = (patternTransform ?? .identity).scale
        let scale = UIScreen.main.scale
        let size = size(frame: frame, context: context).applying(transform)

        let frameWidth = Int((size.width * scale).rounded(.up))
        let frameHeight = Int((size.height * scale).rounded(.up))
        if frameWidth == 0 || frameHeight == 0 { return nil }
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

        let maskContext = SVGContext(base: context.base, graphics: graphics, viewPort: context.viewPort, other: context)
        let patternContentUnits: SVGPatternContentUnitsType
        if viewBox != nil {
            patternContentUnits = .userSpaceOnUse
        } else {
            patternContentUnits = self.patternContentUnits ?? .userSpaceOnUse
        }
        maskContext.push(patternContentUnit: patternContentUnits)
        defer {
            maskContext.popPatternContentUnit()
        }
        graphics.concatenate(transform.scaledBy(x: scale, y: scale))
        switch patternContentUnits {
        case .userSpaceOnUse:
            if let viewBox = viewBox?.toCGRect() {
                let transform = getTransform(viewBox: viewBox, size: size)
                graphics.concatenate(transform)
                maskContext.push(viewBox: viewBox)
            } else {
                maskContext.push(viewBox: context.viewBox)
            }

        case .objectBoundingBox:
            maskContext.push(viewBox: frame)
        }
        if isRoot {
            maskContext.pushTagIdStack()
            maskContext.pushClipIdStack()
            maskContext.pushMaskIdStack()
        }
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
            maskContext.saveGState()
            content.draw(maskContext, index: index, depth: 0, mode: .normal)
            maskContext.restoreGState()
        }
        clipPath?.clipIfNeeded(type: type, frame: frame, context: context, cgContext: graphics)
        if isRoot {
            maskContext.popTagIdStack()
            maskContext.popClipIdStack()
            maskContext.popMaskIdStack()
        }
        guard let image = graphics.makeImage() else { return nil }
        graphics.restoreGState()
        return image
    }

    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {}

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    func pattern(context: inout SVGBaseContext) {
        if let id = id, context.patterns[id] == nil {
            context.setPattern(id: id, value: self)
        }
    }

    func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let preserveAspectRatio = preserveAspectRatio ?? .init(xAlign: .mid, yAlign: .mid, option: .meet)
        return preserveAspectRatio.getTransform(viewBox: viewBox, size: size).translatedBy(x: viewBox.minX, y: viewBox.minY)
    }
}

extension SVGPatternElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case d
        case fill
    }

    func encode(to _: Encoder) throws {
        fatalError()
    }
}
