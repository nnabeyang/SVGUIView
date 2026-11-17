import CoreGraphics
import Foundation

protocol SVGLengthContext {
  var viewBoxSize: CGSize { get }
  var font: SVGUIFont? { get }
  var textScale: Double { get }
  var rootFont: SVGUIFont? { get }
  var viewPort: CGRect { get }
  var writingMode: WritingMode? { get }
  /// The fonts that the `@font-face` rules of the document read, which `font-family` finds first, or `nil` if there
  /// are none, or the context doesn't know the document.
  var documentFonts: DocumentFonts? { get }
}

extension SVGLengthContext {
  var documentFonts: DocumentFonts? { nil }
}

/// What the geometry of an element depends on: lengths, and the box that percentages are relative to.
protocol GeometryContext: SVGLengthContext {
  var viewBox: CGRect { get }
  /// The path that a `<textPath>` lays its characters out along, in the user space of its text, or `nil` if it has
  /// no path data and references no `<path>` or basic shape.
  func path(of textPath: SVGTSpanElement) -> PathMeasure?
  /// The elements outside text that declare the lines of `text-decoration` that its characters have, which draw
  /// those lines with their styles and fonts.
  var textDecorators: TextDecorators { get }
}

/// The closest elements outside text that declare each line of `text-decoration`, which the lines on the characters
/// of text are drawn with, where no element of the text declares them.
struct TextDecorators {
  /// An element that declares lines, after the ones around it.
  private final class Declaration: Sendable {
    let lines: TextDecorationLines
    let element: any SVGDrawableElement
    /// The number of elements that declare lines around the element and itself.
    let depth: Int
    let previous: Declaration?

    init(lines: TextDecorationLines, element: any SVGDrawableElement, previous: Declaration?) {
      self.lines = lines
      self.element = element
      self.depth = (previous?.depth ?? 0) + 1
      self.previous = previous
    }
  }

  /// The innermost element that declares lines, or `nil` if none does, which most contexts are, so that copying a
  /// context costs nothing more.
  private var last: Declaration?

  /// Whether no element declares a line.
  var isEmpty: Bool { last == nil }

  /// Declares lines by an element in the ones that declare lines before it.
  mutating func declare(_ lines: TextDecorationLines, by element: any SVGDrawableElement) {
    last = Declaration(lines: lines, element: element, previous: last)
  }

  /// The element that declares a line, with how deep it is among the elements that declare lines, which is larger
  /// for an element in another, or `nil` if no element declares the line.
  func declaration(of line: TextDecorationLines) -> (element: any SVGDrawableElement, depth: Int)? {
    var declaration = last
    while let current = declaration {
      if current.lines.contains(line) { return (current.element, current.depth) }
      declaration = current.previous
    }
    return nil
  }
}

/// What resolving lengths and building geometry reads while a render tree is built: the rendered rectangle and
/// scale, the viewBox, and the computed values that lengths relative to fonts use.
struct ResolveContext: GeometryContext {
  /// The document whose elements references find, such as the path of a `<textPath>`.
  private(set) var base: SVGBaseContext
  /// The document whose root's font `rem` is relative to, where it isn't ``base``: the document of a `<use>` element
  /// that shows an element of another document, whose copy is in the tree of the `<use>` element.
  private var rootBase: SVGBaseContext?
  let viewPort: CGRect
  /// The scale of the image being rendered.
  let scale: CGFloat
  var viewBox: CGRect
  var style = ComputedStyle.initial
  var textDecorators = TextDecorators()

  var viewBoxSize: CGSize {
    viewBox.size
  }

  var textScale: Double {
    let x = viewPort.width * scale / viewBox.width
    let y = viewPort.height * scale / viewBox.height
    return hypot(x, y) / sqrt(2)
  }

  var font: SVGUIFont? {
    style.font
  }

  var rootFont: SVGUIFont? {
    (rootBase ?? base).root?.style.font
  }

  var documentFonts: DocumentFonts? {
    base.stylesheet.fonts
  }

  var writingMode: WritingMode? {
    style.writingMode
  }

  /// The context for the given element, which resolves lengths with the element's computed values.
  func styled(by element: some SVGElement) -> ResolveContext {
    var context = self
    context.style = element.style
    return context
  }

  /// The lines of `text-decoration` that an element declares, which are drawn on the text in it with its styles and
  /// font, or `nil` if it declares none. A declaration with `var()` declares the lines that it has with the custom
  /// properties of the element substituted.
  static func textDecorations(declaredBy element: some SVGDrawableElement) -> TextDecorationLines? {
    let base = element.base
    // The computed lines have the declared ones, so an element without lines declares none. Text finds the lines that
    // it and its spans declare itself.
    guard !base.style.textDecoration.isEmpty, !(element is SVGTextElement),
      case .value(let lines)? = base.cascaded.declared(
        TextDecorationProperty.self, customProperties: base.style.customProperties),
      !lines.isEmpty
    else { return nil }
    return lines
  }

  /// The context without elements that declare lines of `text-decoration`, for content that isn't drawn in the
  /// descendants of the elements of this context, such as the children of a clip path.
  func withoutTextDecorators() -> ResolveContext {
    var context = self
    context.textDecorators = TextDecorators()
    return context
  }

  /// The context for the content of another document that a `<use>` element shows, whose references find the
  /// elements of that document, and whose `rem` stays relative to the root of the document of the `<use>` element.
  func with(base: SVGBaseContext) -> ResolveContext {
    var context = self
    context.rootBase = rootBase ?? self.base
    context.base = base
    return context
  }

  func with(viewBox: CGRect) -> ResolveContext {
    var context = self
    context.viewBox = viewBox
    return context
  }

  func path(of textPath: SVGTSpanElement) -> PathMeasure? {
    guard let measure = unsidedPath(of: textPath) else { return nil }
    return textPath.isOnRightSide ? measure.reversed() : measure
  }

  /// The path of a `<textPath>` in its direction: its `path` attribute if it has a segment, or the path of the
  /// `<path>` or the basic shape that it references.
  private func unsidedPath(of textPath: SVGTSpanElement) -> PathMeasure? {
    if let data = textPath.pathData {
      let measure = PathMeasure(data)
      if measure.vertexDistances.count > 1 { return measure }
    }
    guard let id = textPath.pathID, let shape = base[id] as? any ShapeGeometry else { return nil }
    let context = styled(by: shape)
    // Text and images have no path data.
    guard let data = shape.markerPath(in: context) else { return nil }
    let style = shape.style
    // The transform of the shape applies to it, and the transforms of its ancestors don't.
    let box =
      style.transformBox == .viewBox
      ? CGRect(origin: .zero, size: viewBoxSize) : shape.path(in: context)?.boundingBoxOfPath ?? .zero
    return PathMeasure(data, transform: context.transform(of: style, box: box))
  }

  /// The transform of computed values about their transform origin in a reference box.
  func transform(of style: ComputedStyle, box: CGRect) -> CGAffineTransform {
    let list = style.transform
    guard !list.functions.isEmpty else { return .identity }
    let matrix = list.matrix(box: box.size, context: self)
    let origin = CGPoint(
      x: box.minX + style.transformOrigin.x.value(total: box.width, context: self),
      y: box.minY + style.transformOrigin.y.value(total: box.height, context: self))
    guard origin != .zero else { return matrix }
    return CGAffineTransform(translationX: -origin.x, y: -origin.y).concatenating(matrix)
      .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
  }
}

/// The references that are being followed, which stop a cycle of references.
///
/// Each kind of reference has a set, which is `nil` until a level is begun. Until then, no reference of that kind is
/// followed, as the drawing code that the elements had did.
struct ReferenceGuard: Sendable {
  /// The `<use>` elements, and the elements that they reference, by the identity of the element objects.
  var uses: Set<ObjectIdentifier>?
  var clipPaths: Set<String>?
  var masks: Set<String>?
  var patterns: Set<String>?
  var markers: Set<String>?
  /// The IDs of the filters whose elements are being drawn, which a `feImage` that draws one of those elements again
  /// would make a cycle of. A new level doesn't empty it, as the source of a filter begins a new guard.
  var filters: Set<String> = []

  struct Kinds: OptionSet {
    let rawValue: Int
    static let uses = Kinds(rawValue: 1 << 0)
    static let clipPaths = Kinds(rawValue: 1 << 1)
    static let masks = Kinds(rawValue: 1 << 2)
    static let patterns = Kinds(rawValue: 1 << 3)
    static let markers = Kinds(rawValue: 1 << 4)
    static let all: Kinds = [.uses, .clipPaths, .masks, .patterns, .markers]
  }

  /// The guard with a new, empty level of the given kinds.
  func beginning(_ kinds: Kinds) -> ReferenceGuard {
    var copy = self
    if kinds.contains(.uses) { copy.uses = [] }
    if kinds.contains(.clipPaths) { copy.clipPaths = [] }
    if kinds.contains(.masks) { copy.masks = [] }
    if kinds.contains(.patterns) { copy.patterns = [] }
    if kinds.contains(.markers) { copy.markers = [] }
    return copy
  }

  /// Adds the element, or returns `false` if it's already being followed or no level is begun.
  mutating func insert(use element: ObjectIdentifier) -> Bool {
    Self.insert(element, into: &uses)
  }

  /// Adds the ID of a `<clipPath>` element, or returns `false` if it's already being followed or no level is begun.
  mutating func insert(clipPath id: String) -> Bool {
    Self.insert(id, into: &clipPaths)
  }

  /// Adds the ID of a `<mask>` element, or returns `false` if it's already being followed or no level is begun.
  mutating func insert(mask id: String) -> Bool {
    Self.insert(id, into: &masks)
  }

  /// Adds the ID of a `<pattern>` element, or returns `false` if it's already being followed or no level is begun.
  mutating func insert(pattern id: String) -> Bool {
    Self.insert(id, into: &patterns)
  }

  /// Adds the ID of a `<marker>` element, or returns `false` if it's already being followed or no level is begun.
  mutating func insert(marker id: String) -> Bool {
    Self.insert(id, into: &markers)
  }

  private static func insert<T>(_ member: T, into set: inout Set<T>?) -> Bool {
    guard set != nil, set!.insert(member).inserted else { return false }
    return true
  }
}
