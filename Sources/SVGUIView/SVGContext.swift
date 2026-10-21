import CoreGraphics
import Foundation

protocol SVGLengthContext {
  var viewBoxSize: CGSize { get }
  var font: SVGUIFont? { get }
  var textScale: Double { get }
  var rootFont: SVGUIFont? { get }
  var viewPort: CGRect { get }
  var writingMode: WritingMode? { get }
}

/// What the geometry of an element depends on: lengths, and the box that `patternContentUnits` of
/// `objectBoundingBox` scales shapes by.
protocol GeometryContext: SVGLengthContext {
  var viewBox: CGRect { get }
  var patternContentUnit: SVGUnitType? { get }
}

struct SVGContext: GeometryContext, @unchecked Sendable {
  let base: SVGBaseContext
  let graphics: CGContext
  let viewPort: CGRect
  /// The scale of the image being rendered, read from the screen before rendering starts.
  let scale: CGFloat

  private let viewBoxStack: Stack<CGRect> = Stack()
  private let patternContentUnitStack = Stack<SVGUnitType>()
  /// The computed values of the element being drawn, which lengths relative to fonts are resolved with.
  private(set) var style = ComputedStyle.initial
  private let tagIdStack = ElementIdStack<ObjectIdentifier>()

  init(base: SVGBaseContext, graphics: CGContext, viewPort: CGRect, scale: CGFloat) {
    self.base = base
    self.graphics = graphics
    self.viewPort = viewPort
    self.scale = scale
  }

  var textScale: Double {
    let x = viewPort.width * scale / viewBox.width
    let y = viewPort.height * scale / viewBox.height
    return hypot(x, y) / sqrt(2)
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
    base.root?.style.font
  }

  var font: SVGUIFont? {
    style.font
  }

  var writingMode: WritingMode? {
    style.writingMode
  }

  /// The context for drawing the given element, which resolves lengths with the element's computed values.
  func styled(by element: some SVGElement) -> SVGContext {
    var context = self
    context.style = element.style
    return context
  }

  func pushTagIdStack() {
    tagIdStack.push()
  }

  func check(tagId: ObjectIdentifier) -> Bool {
    tagIdStack.check(elementId: tagId)
  }

  func remove(tagId: ObjectIdentifier) {
    tagIdStack.remove(elementId: tagId)
  }

  func popTagIdStack() {
    tagIdStack.pop()
  }

  func push(viewBox: CGRect) {
    viewBoxStack.push(viewBox)
  }
}

struct SVGBaseContext {
  /// The parsed document, which the elements to render are made from.
  let document: SVGDocument
  let root: SVGSVGElement?
  let pservers: [String: any SVGGradientServer]
  let contentIdMap: [String: ObjectIdentifier]
  let contents: [ObjectIdentifier: any SVGElement]

  var clipPaths = [String: SVGClipPathElement]()
  var masks = [String: SVGMaskElement]()
  var patterns = [String: SVGPatternElement]()
  var filters = [String: SVGFilterElement]()

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

  subscript(id: String) -> (any SVGDrawableElement)? {
    guard let idx = contentIdMap[id],
      let element = contents[idx] as? (any SVGDrawableElement)
    else { return nil }
    return element
  }
}

private class Stack<T>: @unchecked Sendable {
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
      let index = value.lastIndex(of: elementId)
    else { return }
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
