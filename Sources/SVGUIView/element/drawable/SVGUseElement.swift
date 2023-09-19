import UIKit

struct SVGUseElement: SVGDrawableElement {
    var type: SVGElementName {
        .use
    }

    let base: SVGBaseElement
    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?
    let parentId: String?
    let attributes: [String: String]
    let contentIds: [Int]

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)
        x = SVGLength(attributes["x"])
        y = SVGLength(attributes["y"])
        width = SVGLength(attributes["width"])
        height = SVGLength(attributes["height"])
        parentId = Self.parseLink(description: attributes["href"] ?? attributes["xlink:href"])
        self.attributes = attributes
        self.contentIds = contentIds
    }

    init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
        fatalError()
    }

    init(other: Self, attributes: [String: String]) {
        base = SVGBaseElement(other: other.base, attributes: attributes)
        x = other.x
        y = other.y
        width = other.width
        height = other.height
        parentId = other.parentId
        self.attributes = other.attributes
        contentIds = other.contentIds
    }

    init(other: SVGUseElement, index: Int, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, index: index, css: css)
        x = other.x
        y = other.y
        width = other.width
        height = other.height
        parentId = other.parentId
        attributes = other.attributes
        contentIds = other.contentIds
    }

    private static func parseLink(description: String?) -> String? {
        guard let description = description else { return nil }
        let hashId = description.trimmingCharacters(in: .whitespaces)
        if hashId.hasPrefix("#") {
            return String(hashId.dropFirst())
        }
        return nil
    }

    func style(with _: CSSStyle, at index: Int) -> any SVGElement {
        Self(other: self, index: index, css: SVGUIStyle(decratations: [:]))
    }

    private func getParent(context: SVGContext, index: Int) -> (Int, any SVGDrawableElement)? {
        _ = context.check(tagId: index)
        guard let parentId = parentId,
              let (newIndex, element) = context[parentId],
              context.check(tagId: newIndex),
              !element.contains(index: index, context: context)
        else {
            return nil
        }
        let x = x?.value(context: context, mode: .width) ?? 0
        let y = y?.value(context: context, mode: .height) ?? 0
        let transform = CGAffineTransform(translationX: x, y: y)
        context.concatenate(transform)
        let parentElement = element.use(attributes: attributes)
        return (newIndex, parentElement)
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        guard let index = index,
              let (_, element) = getParent(context: context, index: index)
        else {
            return nil
        }
        return element.toBezierPath(context: context)
    }

    func draw(_ context: SVGContext, index: Int, depth: Int, mode: DrawMode) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        let gContext = context.graphics
        gContext.saveGState()
        defer {
            gContext.restoreGState()
        }
        switch mode {
        case .root, .filter:
            context.pushTagIdStack()
        default:
            break
        }
        guard let (newIndex, newElement) = getParent(context: context, index: index) else { return }
        newElement.draw(context, index: newIndex, depth: depth + 1, mode: .normal)
        switch mode {
        case .root, .filter:
            context.popTagIdStack()
        default:
            break
        }
    }

    func contains(index: Int, context _: SVGContext) -> Bool {
        contentIds.contains(index)
    }
}

extension SVGUseElement: Encodable {
    func encode(to _: Encoder) throws {
        fatalError()
    }
}
