import CoreGraphics
import Foundation

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

  /// The state that the drawing code of elements reads, for the effects that it still draws.
  func legacy(_ guard: ReferenceGuard) -> LegacyState {
    LegacyState(viewBox: viewBox, patternContentUnit: patternContentUnit, style: style, guard: `guard`)
  }
}

/// The references that are being followed, which stop a cycle of references.
///
/// Each kind of reference has a set, which is `nil` until a level is begun, and then no reference of that kind is
/// followed, as with the stacks of IDs of `SVGContext` with no level.
struct ReferenceGuard: Sendable {
  /// The `<use>` elements, and the elements that they reference, by the identity of the element objects.
  var uses: Set<ObjectIdentifier>?
  var clipPaths: Set<String>?
  var masks: Set<String>?
  var patterns: Set<String>?

  struct Kinds: OptionSet {
    let rawValue: Int
    static let uses = Kinds(rawValue: 1 << 0)
    static let clipPaths = Kinds(rawValue: 1 << 1)
    static let masks = Kinds(rawValue: 1 << 2)
    static let patterns = Kinds(rawValue: 1 << 3)
    static let all: Kinds = [.uses, .clipPaths, .masks, .patterns]
  }

  /// The guard with a new, empty level of the given kinds.
  func beginning(_ kinds: Kinds) -> ReferenceGuard {
    var copy = self
    if kinds.contains(.uses) { copy.uses = [] }
    if kinds.contains(.clipPaths) { copy.clipPaths = [] }
    if kinds.contains(.masks) { copy.masks = [] }
    if kinds.contains(.patterns) { copy.patterns = [] }
    return copy
  }

  /// Adds the element, or returns `false` if it's already being followed or no level is begun.
  mutating func insert(use element: ObjectIdentifier) -> Bool {
    guard uses != nil, uses!.insert(element).inserted else { return false }
    return true
  }
}

/// The state of the drawing code of elements when it draws an effect, from which `SVGContext` is made again.
struct LegacyState: Sendable {
  let viewBox: CGRect
  let patternContentUnit: SVGUnitType?
  let style: ComputedStyle
  let `guard`: ReferenceGuard
}
