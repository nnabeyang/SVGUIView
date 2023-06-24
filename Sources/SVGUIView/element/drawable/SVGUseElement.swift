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

    init(other: SVGUseElement, css _: SVGUIStyle) {
        self = other
    }

    private static func parseLink(description: String?) -> String? {
        guard let description = description else { return nil }
        let hashId = description.trimmingCharacters(in: .whitespaces)
        if hashId.hasPrefix("#") {
            return String(hashId.dropFirst())
        }
        return nil
    }

    func style(with _: CSSStyle) -> SVGElement {
        self
    }

    func toBezierPath(context: SVGContext) -> UIBezierPath? {
        guard let parentId = parentId,
              let (_, element) = context[parentId] else { return nil }
        let gContext = context.graphics
        gContext.saveGState()
        defer {
            gContext.restoreGState()
        }
        let size = context.viewBox.size
        let x = x?.value(total: size.width) ?? 0
        let y = y?.value(total: size.height) ?? 0
        let transform = CGAffineTransform(translationX: x, y: y)
        context.concatenate(transform)
        let newElement = element.use(attributes: attributes)
        return newElement.toBezierPath(context: context)
    }

    func draw(_ context: SVGContext, index: Int, depth: Int) {
        guard !context.detectCycles(type: type, depth: depth) else { return }
        guard let parentId = parentId,
              let (newIndex, element) = context[parentId],
              !element.contains(index: index, context: context) else { return }
        let gContext = context.graphics
        gContext.saveGState()
        defer {
            gContext.restoreGState()
        }
        let size = context.viewBox.size
        let x = x?.value(total: size.width) ?? 0
        let y = y?.value(total: size.height) ?? 0
        let transform = CGAffineTransform(translationX: x, y: y)
        context.concatenate(transform)
        let newElement = element.use(attributes: attributes)
        newElement.draw(context, index: newIndex, depth: depth + 1)
    }

    func contains(index: Int, context: SVGContext) -> Bool {
        guard let parentId = parentId,
              let (_, element) = context[parentId]
        else {
            return false
        }
        if let id = id, id == parentId {
            return true
        }
        if let id = id, let (selfIndex, _) = context[id], selfIndex == index {
            return true
        }
        return element.contains(index: index, context: context)
    }
}

extension SVGUseElement: Encodable {
    func encode(to _: Encoder) throws {
        fatalError()
    }
}
