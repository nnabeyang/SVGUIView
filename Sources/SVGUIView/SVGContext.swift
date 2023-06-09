import UIKit

struct SVGContext {
    let base: SVGBaseContext
    let graphics: CGContext

    private let startDetectingCyclesAfter: Int
    private let viewBoxStack: Stack<CGRect> = Stack()
    private let fontStack: Stack<SVGUIFont> = Stack()
    private let fillStack: Stack<SVGFill> = Stack()
    private let colorStack: Stack<SVGUIColor> = Stack()
    private let strokeStack: Stack<SVGUIStroke> = Stack()
    private let textAnchorStack: Stack<TextAnchor> = Stack()
    private let clipRuleStack: Stack<Bool> = Stack()
    private let clipIdStack = ElementIdStack<String>()
    private let tagIdStack = ElementIdStack<Int>()

    init(base: SVGBaseContext, graphics: CGContext, startDetectingCyclesAfter: Int = 1000) {
        self.base = base
        self.graphics = graphics
        self.startDetectingCyclesAfter = startDetectingCyclesAfter
    }

    var pservers: [String: any SVGGradientServer] {
        base.pservers
    }

    var contents: [SVGElement] {
        base.contents
    }

    var clipPaths: [String: SVGClipPathElement] {
        base.clipPaths
    }

    subscript(id: String) -> (Index: Int, element: any SVGDrawableElement)? {
        base[id]
    }

    func detectCycles(type: SVGElementName, depth: Int) -> Bool {
        let maybeCycling = depth >= startDetectingCyclesAfter
        if maybeCycling {
            SVGUIView.logger.debug("encountered a cycle via \(type.rawValue)")
        }
        return maybeCycling
    }

    var viewBox: CGRect {
        viewBoxStack.last!
    }

    var font: SVGUIFont? {
        fontStack.last
    }

    var fill: SVGFill? {
        fillStack.last
    }

    var color: SVGUIColor? {
        colorStack.last
    }

    var stroke: SVGUIStroke? {
        strokeStack.last
    }

    var textAnchor: TextAnchor? {
        textAnchorStack.last
    }

    func pushClipIdStack() {
        clipIdStack.push()
    }

    func check(clipId: String) -> Bool {
        clipIdStack.check(elementId: clipId)
    }

    func remove(clipId: String) {
        clipIdStack.remove(elementId: clipId)
    }

    func popClipIdStack() {
        clipIdStack.pop()
    }

    func pushTagIdStack() {
        tagIdStack.push()
    }

    func check(tagId: Int) -> Bool {
        tagIdStack.check(elementId: tagId)
    }

    func remove(tagId: Int) {
        tagIdStack.remove(elementId: tagId)
    }

    func popTagIdStack() {
        clipIdStack.pop()
    }

    func push(viewBox: CGRect) {
        viewBoxStack.push(viewBox)
    }

    func push(font: SVGUIFont) {
        let font = SVGUIFont(lhs: font, rhs: self.font)
        fontStack.push(font)
    }

    func push(fill: SVGFill) {
        fillStack.push(fill)
    }

    func push(color: SVGUIColor) {
        colorStack.push(color)
    }

    func push(stroke: SVGUIStroke) {
        let stroke = SVGUIStroke(lhs: stroke, rhs: self.stroke)
        strokeStack.push(stroke)
    }

    func push(textAnchor: TextAnchor) {
        textAnchorStack.push(textAnchor)
    }

    @discardableResult
    func popViewBox() -> CGRect? {
        viewBoxStack.pop()
    }

    @discardableResult
    func popFont() -> SVGUIFont? {
        fontStack.pop()
    }

    @discardableResult
    func popFill() -> SVGFill? {
        fillStack.pop()
    }

    @discardableResult
    func popColor() -> SVGUIColor? {
        colorStack.pop()
    }

    @discardableResult
    func popStroke() -> SVGUIStroke? {
        strokeStack.pop()
    }

    @discardableResult
    func popTextAnchor() -> TextAnchor? {
        textAnchorStack.pop()
    }

    func saveGState() {
        graphics.saveGState()
    }

    func concatenate(_ transform: CGAffineTransform) {
        graphics.concatenate(transform)
    }

    func restoreGState() {
        graphics.restoreGState()
    }

    func setAlpha(_ rawAlpha: CGFloat) {
        graphics.setAlpha(rawAlpha)
    }
}

struct SVGBaseContext {
    let pservers: [String: any SVGGradientServer]
    let contentIdMap: [String: Int]
    let contents: [SVGElement]

    var clipPaths = [String: SVGClipPathElement]()
    private let clipRuleStack: Stack<Bool> = Stack()

    var root: SVGSVGElement? {
        contents.last as? SVGSVGElement
    }

    var clipRule: Bool? {
        clipRuleStack.last
    }

    mutating func setClipPath(id: String, value: SVGClipPathElement) {
        if clipPaths[id] == nil {
            clipPaths[id] = value
        }
    }

    subscript(id: String) -> (Index: Int, element: any SVGDrawableElement)? {
        guard let idx = contentIdMap[id],
              let element = contents[idx] as? (any SVGDrawableElement) else { return nil }
        return (Index: idx, element: element)
    }

    func push(clipRule: Bool) {
        clipRuleStack.push(clipRule)
    }

    @discardableResult
    func popClipRule() -> Bool? {
        clipRuleStack.pop()
    }
}

private class Stack<T> {
    var fonts: [T] = []
    var last: T? {
        fonts.last
    }

    func push(_ font: T) {
        fonts.append(font)
    }

    func pop() -> T? {
        fonts.popLast()
    }
}

private class ElementIdStack<T: Equatable> {
    var values = [[T]]()

    func check(elementId: T) -> Bool {
        if values.last?.contains(elementId) ?? false {
            return false
        }
        values[values.count - 1].append(elementId)
        return true
    }

    func remove(elementId: T) {
        guard var value = values.last,
              let index = value.lastIndex(of: elementId) else { return }
        value.remove(at: index)
        values[values.count - 1] = value
    }

    func push() {
        values.append([])
    }

    @discardableResult
    func pop() -> [T]? {
        values.popLast()
    }
}
