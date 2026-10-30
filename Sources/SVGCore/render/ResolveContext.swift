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

/// What resolving lengths and building geometry reads while a render tree is built: the rendered rectangle and
/// scale, the viewBox and the content units of a pattern of the element, and the computed values that lengths
/// relative to fonts use.
struct ResolveContext: GeometryContext {
  let base: SVGBaseContext
  let viewPort: CGRect
  /// The scale of the image being rendered.
  let scale: CGFloat
  var viewBox: CGRect
  var patternContentUnit: SVGUnitType?
  var style = ComputedStyle.initial

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
    base.root?.style.font
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

  func with(viewBox: CGRect) -> ResolveContext {
    var context = self
    context.viewBox = viewBox
    return context
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
