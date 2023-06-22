import UIKit

struct SVGContext {
    let base: SVGBaseContext
    let graphics: CGContext

    private let viewBoxStack: Stack<CGRect> = Stack()
    private let fontStack: Stack<SVGUIFont> = Stack()
    private let fillStack: Stack<SVGFill> = Stack()
    private let colorStack: Stack<SVGUIColor> = Stack()
    private let strokeStack: Stack<SVGUIStroke> = Stack()
    private let textAnchorStack: Stack<TextAnchor> = Stack()

    init(base: SVGBaseContext, graphics: CGContext) {
        self.base = base
        self.graphics = graphics
    }

    var pservers: [String: any SVGGradientServer] {
        base.pservers
    }

    var contents: [SVGElement] {
        base.contents
    }

    subscript(id: String) -> (Index: Int, element: any SVGDrawableElement)? {
        base[id]
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
