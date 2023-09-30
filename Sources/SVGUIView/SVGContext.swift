import UIKit

protocol SVGLengthContext {
    var viewBoxSize: CGSize { get }
    var font: SVGUIFont? { get }
    var rootFont: SVGUIFont? { get }
    var viewPort: CGRect { get }
    var writingMode: WritingMode? { get }
}

struct SVGContext: SVGLengthContext {
    let base: SVGBaseContext
    let graphics: CGContext
    let viewPort: CGRect

    private let startDetectingCyclesAfter: Int
    private let viewBoxStack: Stack<CGRect> = Stack()
    private let patternContentUnitStack = Stack<SVGUnitType>()
    private let fontStack: Stack<SVGUIFont> = Stack()
    private let writingModeStack = Stack<WritingMode>()
    private let fillStack: Stack<SVGFill> = Stack()
    private let colorStack: Stack<SVGUIColor> = Stack()
    private let strokeStack: Stack<SVGUIStroke> = Stack()
    private let textAnchorStack: Stack<TextAnchor> = Stack()
    private let clipRuleStack: Stack<Bool> = Stack()
    private let clipIdStack = ElementIdStack<String>()
    private let maskIdStack = ElementIdStack<String>()
    private let patternIdStack: ElementIdStack<String>
    private let tagIdStack = ElementIdStack<Int>()
    private let initCtm: CGAffineTransform

    init(base: SVGBaseContext, graphics: CGContext, viewPort: CGRect, startDetectingCyclesAfter: Int = 1000) {
        self.base = base
        self.graphics = graphics
        initCtm = graphics.ctm
        self.viewPort = viewPort
        self.startDetectingCyclesAfter = startDetectingCyclesAfter
        patternIdStack = ElementIdStack<String>()
    }

    init(base: SVGBaseContext, graphics: CGContext, viewPort: CGRect, startDetectingCyclesAfter: Int = 1000, other: Self) {
        self.base = base
        self.graphics = graphics
        initCtm = graphics.ctm
        self.viewPort = viewPort
        self.startDetectingCyclesAfter = startDetectingCyclesAfter
        patternIdStack = other.patternIdStack
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

    var masks: [String: SVGMaskElement] {
        base.masks
    }

    var patterns: [String: SVGPatternElement] {
        base.patterns
    }

    var filters: [String: SVGFilterElement] {
        base.filters
    }

    var transform: CGAffineTransform {
        graphics.ctm.concatenating(initCtm.inverted())
            .scaledBy(x: 1 / UIScreen.main.scale, y: 1 / UIScreen.main.scale)
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

    var viewBoxSize: CGSize {
        viewBox.size
    }

    var patternContentUnit: SVGUnitType? {
        patternContentUnitStack.last
    }

    var rootFont: SVGUIFont? {
        fontStack.first
    }

    var font: SVGUIFont? {
        fontStack.last
    }

    var writingMode: WritingMode? {
        writingModeStack.last
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

    func pushMaskIdStack() {
        maskIdStack.push()
    }

    func check(maskId: String) -> Bool {
        maskIdStack.check(elementId: maskId)
    }

    func remove(maskId: String) {
        maskIdStack.remove(elementId: maskId)
    }

    func popMaskIdStack() {
        maskIdStack.pop()
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

    func pushPatternIdStack() {
        patternIdStack.push()
    }

    func check(patternId: String) -> Bool {
        patternIdStack.check(elementId: patternId)
    }

    func remove(patternId: String) {
        patternIdStack.remove(elementId: patternId)
    }

    func popPatternIdStack() {
        patternIdStack.pop()
    }

    func push(viewBox: CGRect) {
        viewBoxStack.push(viewBox)
    }

    func push(patternContentUnit: SVGUnitType) {
        patternContentUnitStack.push(patternContentUnit)
    }

    func push(writingMode: WritingMode) {
        writingModeStack.push(writingMode)
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
    func popPatternContentUnit() -> SVGUnitType? {
        patternContentUnitStack.pop()
    }

    @discardableResult
    func popWritingMode() -> WritingMode? {
        writingModeStack.pop()
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
    var masks = [String: SVGMaskElement]()
    var patterns = [String: SVGPatternElement]()
    var filters = [String: SVGFilterElement]()
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

    mutating func setMask(id: String, value: SVGMaskElement) {
        if masks[id] == nil {
            masks[id] = value
        }
    }

    mutating func setPattern(id: String, value: SVGPatternElement) {
        if patterns[id] == nil {
            patterns[id] = value
        }
    }

    mutating func setFilter(id: String, value: SVGFilterElement) {
        if filters[id] == nil {
            filters[id] = value
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

    var first: T? {
        fonts.first
    }

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
        if values.last?.contains(elementId) ?? true {
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
