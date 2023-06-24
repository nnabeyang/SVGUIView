import UIKit

struct SVGClipPathElement: SVGElement {
    var type: SVGElementName {
        .clipPath
    }

    let contentIds: [Int]
    let transform: CGAffineTransform?
    let userSpace: Bool?
    let clipRule: Bool?
    let clipPath: SVGClipPath?
    let id: String?

    init(attributes: [String: String], contentIds: [Int]) {
        id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
        userSpace = attributes["clipPathUnits"].flatMap { $0 == "userSpaceOnUse" }
        clipRule = attributes["clip-rule"].map { $0.trimmingCharacters(in: .whitespaces) == "evenodd" }
        clipPath = SVGClipPath(description: attributes["clip-path", default: ""])
        transform = CGAffineTransform(description: attributes["transform", default: ""])
        self.contentIds = contentIds
    }

    init(other: Self, css _: SVGUIStyle) {
        self = other
    }

    init(other: Self, clipRule: Bool?) {
        id = other.id
        userSpace = other.userSpace
        self.clipRule = other.clipRule ?? clipRule
        clipPath = other.clipPath
        contentIds = other.contentIds
        transform = other.transform
    }

    func toBezierPath(context: SVGContext, frame: CGRect) -> UIBezierPath {
        let transform: CGAffineTransform
        let userSpace = userSpace ?? true
        if userSpace {
            transform = self.transform ?? .identity
        } else {
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
            guard let bezierPath = content.toClipedBezierPath(context: context) else { continue }
            bezierPath.apply(content.transform.concatenating(transform))
            var tpath = bezierPath.cgPath
            let clipRule = content.clipRule ?? clipRule ?? false
            if case let .url(id) = content.clipPath,
               context.check(clipId: id),
               let path = context.clipPaths[id]?.toBezierPath(context: context, frame: frame)
            {
                tpath = tpath.xintersection(path.cgPath, using: .winding)
                context.remove(clipId: id)
            }
            if rootPath == nil {
                rootPath = tpath.xnormalized(using: clipRule ? .evenOdd : .winding)
            } else {
                rootPath = rootPath?.xunion(tpath, using: clipRule ? .evenOdd : .winding)
            }
        }
        if case let .url(id) = clipPath,
           context.check(clipId: id),
           let path = context.clipPaths[id]?.toBezierPath(context: context, frame: frame)
        {
            context.remove(clipId: id)
            rootPath = rootPath?.xintersection(path.cgPath, using: .winding)
        }
        return rootPath.map { UIBezierPath(cgPath: $0) } ?? UIBezierPath()
    }

    func draw(_: SVGContext, index _: Int, depth _: Int) {}

    func style(with _: CSSStyle) -> SVGElement {
        self
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
