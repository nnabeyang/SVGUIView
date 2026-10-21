import CoreGraphics
import Foundation

/// The identity of a node of a render tree: the element that it comes from, and the `<use>` elements that show
/// it, from the outermost one. A renderer matches the nodes of a new render tree with the previous one by it.
struct RenderID: Hashable, Sendable {
  let element: ElementID
  let instance: [ElementID]
}

/// An immutable path, which a render tree holds. `CGPath` isn't `Sendable`, but a path that nothing changes can be
/// read from any thread.
struct RenderPath: @unchecked Sendable {
  let cgPath: CGPath

  init(_ path: CGPath) {
    cgPath = path.copy() ?? path
  }
}

/// What painting a document needs, and nothing more.
///
/// A render tree is built for a rendering at a size and a scale, because lengths in percentages and the sizes of
/// text depend on them.
struct RenderTree: Sendable {
  /// The transforms that fit the root `<svg>` element into the rendered rectangle, which are applied one after
  /// another.
  let rootTransforms: [CGAffineTransform]
  let root: RenderNode?
}

indirect enum RenderNode: Sendable {
  /// A shape, text or an image, or an element that only makes an empty layer, such as `<defs>`.
  case shape(ShapeNode)
  case group(GroupNode)
  /// An `<svg>` element.
  case viewport(ViewportNode)
  case use(UseNode)
  /// An element with a filter, which the filter element applies until filters move into the render tree.
  case legacyFiltered(LegacyFilteredNode)
}

struct ShapeNode: Sendable {
  let id: RenderID
  let transform: CGAffineTransform
  /// The shape and its bounds, or `nil` for an element without a shape.
  let geometry: Geometry?
  let clip: ClipPathEffect?
  let mask: MaskApplication
  let opacity: CGFloat
  /// What the shape paints, or `nil` if it's hidden or has no shape.
  let content: ShapeContent?
}

struct Geometry: Sendable {
  let path: RenderPath
  /// The bounds that units relative to the element use, which differ from the bounds of the path for a line and
  /// for text.
  let frame: CGRect
}

enum ShapeContent: Sendable {
  case vector(fill: FillPaint?, stroke: StrokeStyle?, fillRule: CGPathDrawingMode)
  /// An image, or `nil` if its data can't be decoded.
  case image(CGImage?, stroke: StrokeStyle?)
}

enum FillPaint: Sendable {
  case color(CGColor)
  /// A gradient, or `nil` for one without a stop with a color, which paints nothing.
  case gradient(GradientPaint?)
  /// A pattern, or `nil` for one whose tile can't be made, which paints nothing. A cycle of patterns paints black
  /// instead.
  case pattern(PatternPaint?)
}

struct StrokeStyle: Sendable {
  /// The color of the stroke, or `nil` for a paint server, which isn't supported on strokes and keeps the stroke
  /// color of the context.
  let color: CGColor?
  /// The dashes, or `nil` if none of them has a length.
  let dashes: [CGFloat]?
  let dashOffset: CGFloat
  let width: CGFloat
  let cap: CGLineCap
  let join: CGLineJoin
  let miterLimit: CGFloat
}

enum MaskApplication: Sendable {
  case none
  /// A line that has a mask and no area clips everything.
  case clipToZero
  case mask(MaskEffect)
}

struct GroupNode: Sendable {
  let id: RenderID
  let transform: CGAffineTransform
  let opacity: CGFloat
  let clip: ClipPathEffect?
  let children: [RenderNode]
}

struct ViewportNode: Sendable {
  let id: RenderID
  /// The translation by `x` and `y`.
  let translation: CGAffineTransform
  /// The content, or `nil` if the viewport has no area.
  let content: ViewportContent?
}

struct ViewportContent: Sendable {
  let viewBoxTransform: CGAffineTransform
  let overflowClip: CGRect?
  let clip: ClipPathEffect?
  let children: [RenderNode]
}

struct UseNode: Sendable {
  let id: RenderID
  let transform: CGAffineTransform
  let clip: ClipPathEffect?
  /// The referenced content, or `nil` if there is none or showing it would make a cycle.
  let instance: UseInstance?
}

struct UseInstance: Sendable {
  /// The translation by `x` and `y`.
  let translation: CGAffineTransform
  let opacity: CGFloat
  let content: RenderNode?
}

struct LegacyFilteredNode: Sendable {
  let element: any SVGDrawableElement
  let filter: SVGFilterElement
  /// The state that the filter element resolves lengths and finds the bounds of the element with.
  let legacy: LegacyState
  /// The element without its filter, which is the source image of the filter.
  let source: RenderNode?
}
