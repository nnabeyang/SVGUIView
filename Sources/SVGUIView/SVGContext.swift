import UIKit

struct SVGContext {
    let pserver: SVGPaintServer
    let viewBox: CGRect
    let graphics: CGContext
    let transform: CGAffineTransform

    private let fontStack: Stack<SVGUIFont> = Stack()
    private let fillStack: Stack<SVGFill> = Stack()
    private let colorStack: Stack<SVGUIColor> = Stack()
    private let strokeStack: Stack<SVGUIStroke> = Stack()
    private let textAnchorStack: Stack<TextAnchor> = Stack()

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
