import UIKit

struct SVGUseElement: SVGDrawableElement {
    var type: SVGElementName {
        .use
    }

    let base: SVGBaseElement
    let x: ElementLength?
    let y: ElementLength?
    let width: ElementLength?
    let height: ElementLength?
    let parentId: String?
    let attributes: [String: String]
    let contentIds: [Int]

    init(attributes: [String: String], contentIds: [Int]) {
        base = SVGBaseElement(attributes: attributes)
        x = .init(attributes["x"])
        y = .init(attributes["y"])
        width = .init(attributes["width"])
        height = .init(attributes["height"])
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

        let size = context.viewBox.size
        let x = x?.value(total: size.width) ?? 0
        let y = y?.value(total: size.height) ?? 0
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

    func draw(_ context: SVGContext, index: Int, depth: Int, isRoot: Bool) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        let gContext = context.graphics
        gContext.saveGState()
        defer {
            gContext.restoreGState()
        }
        if isRoot {
            context.pushTagIdStack()
        }
        guard let (newIndex, newElement) = getParent(context: context, index: index) else { return }
        newElement.draw(context, index: newIndex, depth: depth + 1, isRoot: false)
        if isRoot {
            context.popTagIdStack()
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
