import UIKit

struct SVGClipPathElement: SVGElement {
    var type: SVGElementName {
        .clipPath
    }

    let contentIds: [Int]
    let transform: CGAffineTransform?
    let clipPathUnits: SVGUnitType?
    let clipRule: Bool?
    let clipPath: SVGClipPath?
    let id: String?
    let index: Int?

    init(attributes: [String: String], contentIds: [Int]) {
        id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
        index = nil
        clipPathUnits = SVGUnitType(rawValue: attributes["clipPathUnits", default: ""])
        clipRule = attributes["clip-rule"].map { $0.trimmingCharacters(in: .whitespaces) == "evenodd" }
        clipPath = SVGClipPath(description: attributes["clip-path", default: ""])
        transform = CGAffineTransform(description: attributes["transform", default: ""])
        self.contentIds = contentIds
    }

    init(other: Self, index: Int, css _: SVGUIStyle) {
        id = other.id
        self.index = index
        clipPathUnits = other.clipPathUnits
        clipRule = other.clipRule
        clipPath = other.clipPath
        transform = other.transform
        contentIds = other.contentIds
    }

    init(other: Self, clipRule: Bool?) {
        id = other.id
        index = other.index
        clipPathUnits = other.clipPathUnits
        self.clipRule = other.clipRule ?? clipRule
        clipPath = other.clipPath
        contentIds = other.contentIds
        transform = other.transform
    }

    func clip(type: SVGElementName, frame: CGRect, context: SVGContext, cgContext: CGContext) -> Bool {
        if #available(iOS 16.0, *), type != .line {
            let bezierPath = toBezierPath(context: context, frame: frame)
            guard !bezierPath.isEmpty else { return false }
            bezierPath.addClip()
            return true
        } else {
            guard let maskImage = maskImage(frame: frame, context: context) else { return false }
            cgContext.clip(to: frame, mask: maskImage)
            return true
        }
    }

    private func maskImage(frame: CGRect, context: SVGContext) -> CGImage? {
        let size = frame.size
        let scale = UIScreen.main.scale
        let frameWidth = Int((size.width * scale).rounded(.up))
        let frameHeight = Int((size.height * scale).rounded(.up))
        let bytesPerRow = 4 * frameWidth
        guard let graphics = CGContext(data: nil,
                                       width: frameWidth,
                                       height: frameHeight,
                                       bitsPerComponent: 8,
                                       bytesPerRow: bytesPerRow,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)
        else {
            return nil
        }

        let transform: CGAffineTransform
        let clipPathUnits = clipPathUnits ?? .userSpaceOnUse
        let t = (self.transform ?? .identity).concatenating(CGAffineTransform(scaleX: scale, y: scale))

        switch clipPathUnits {
        case .userSpaceOnUse:
            transform = t
                .translatedBy(x: -frame.minX, y: -frame.minY)
        case .objectBoundingBox:
            transform = t
                .scaledBy(x: size.width, y: size.height)
        }

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
            guard let bezierPath = content.toBezierPath(context: context) else { continue }
            graphics.saveGState()
            content.transform.map {
                graphics.concatenate($0)
            }

            content.clipPath?.clipIfNeeded(type: content.type, frame: frame, context: context, cgContext: graphics)
            let clipRule = content.clipRule ?? clipRule ?? false
            graphics.addPath(bezierPath.cgPath)
            graphics.drawPath(using: clipRule ? .eoFill : .fill)
            graphics.restoreGState()
        }
        clipPath?.clipIfNeeded(type: type, frame: frame, context: context, cgContext: context.graphics)
        let image = graphics.makeImage()
        graphics.restoreGState()
        return image
    }

    @available(iOS 16.0, *)
    func toBezierPath(context: SVGContext, frame: CGRect) -> UIBezierPath {
        let transform: CGAffineTransform
        let clipPathUnits = clipPathUnits ?? .userSpaceOnUse
        switch clipPathUnits {
        case .userSpaceOnUse:
            transform = self.transform ?? .identity
        case .objectBoundingBox:
            transform = (self.transform ?? .identity)
                .translatedBy(x: frame.origin.x, y: frame.origin.y)
                .scaledBy(x: frame.width, y: frame.height)
        }
        var rootPath: CGPath?
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
            guard let bezierPath = content.toClippedBezierPath(context: context) else { continue }
            bezierPath.apply((content.transform ?? .identity).concatenating(transform))
            var tpath = bezierPath.cgPath
            let clipRule = content.clipRule ?? clipRule ?? false
            if case let .url(id) = content.clipPath,
               context.check(clipId: id),
               let path = context.clipPaths[id]?.toBezierPath(context: context, frame: frame)
            {
                tpath = tpath.intersection(path.cgPath, using: .winding)
                context.remove(clipId: id)
            }
            if rootPath == nil {
                rootPath = tpath.normalized(using: clipRule ? .evenOdd : .winding)
            } else {
                rootPath = rootPath?.union(tpath, using: clipRule ? .evenOdd : .winding)
            }
        }

        if case let .url(id) = clipPath,
           context.check(clipId: id),
           let path = context.clipPaths[id]?.toBezierPath(context: context, frame: frame)
        {
            context.remove(clipId: id)
            rootPath = rootPath?.intersection(path.cgPath, using: .winding)
        }
        return rootPath.map { UIBezierPath(cgPath: $0) } ?? UIBezierPath()
    }

    func drawWithoutFilter(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {}
    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {}

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    func clip(context: inout SVGBaseContext) {
        if let id = id, context.clipPaths[id] == nil {
            context.setClipPath(id: id, value: .init(other: self, clipRule: context.clipRule))
        }
    }
}

extension SVGClipPathElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case d
        case fill
    }

    func encode(to _: Encoder) throws {
        fatalError()
    }
}
