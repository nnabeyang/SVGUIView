import CoreGraphics
import Foundation

/// The identity of a node of a render tree: the element that it comes from, and the `<use>` elements that show
/// it, from the outermost one. A renderer matches the nodes of a new render tree with the previous one by it.
package struct RenderID: Hashable, Sendable {
  package let element: ElementID
  package let instance: [ElementID]
}

/// An immutable path, which a render tree holds. `CGPath` isn't `Sendable`, but a path that nothing changes can be
/// read from any thread.
package struct RenderPath: @unchecked Sendable {
  package let cgPath: CGPath

  init(_ path: CGPath) {
    cgPath = path.copy() ?? path
  }
}

/// What painting a document needs, and nothing more.
///
/// A render tree is built for a rendering at a size and a scale, because lengths in percentages and the sizes of
/// text depend on them.
package struct RenderTree: Sendable {
  /// The transforms that fit the root `<svg>` element into the rendered rectangle, which are applied one after
  /// another.
  package let rootTransforms: [CGAffineTransform]
  package let root: RenderNode?
}

package indirect enum RenderNode: Sendable {
  /// A shape, text or an image, or an element that only makes an empty layer, such as `<defs>`.
  case shape(ShapeNode)
  case group(GroupNode)
  /// An `<svg>` element.
  case viewport(ViewportNode)
  case use(UseNode)
  /// An element with a filter.
  case filtered(FilteredNode)
}

package struct ShapeNode: Sendable {
  package let id: RenderID
  package let transform: CGAffineTransform
  /// The shape and its bounds, or `nil` for an element without a shape.
  package let geometry: Geometry?
  package let clip: ClipPathEffect?
  package let mask: MaskApplication
  package let opacity: CGFloat
  /// What the shape paints, or `nil` if it's hidden or has no shape.
  package let content: ShapeContent?
}

package struct Geometry: Sendable {
  package let path: RenderPath
  /// The bounds that units relative to the element use, which differ from the bounds of the path for a line and
  /// for text.
  package let frame: CGRect
}

package enum ShapeContent: Sendable {
  case vector(fill: FillPaint?, stroke: StrokeStyle?, fillRule: CGPathDrawingMode)
  /// An image, or `nil` if its data can't be decoded.
  case image(CGImage?, stroke: StrokeStyle?)
}

package enum FillPaint: Sendable {
  case color(CGColor)
  /// A gradient, or `nil` for one without a stop with a color, which paints nothing.
  case gradient(GradientPaint?)
  /// A pattern, or `nil` for one whose tile can't be made, which paints nothing. A cycle of patterns paints black
  /// instead.
  case pattern(PatternPaint?)
}

package struct StrokeStyle: Sendable {
  /// The color of the stroke, or `nil` for a paint server, which isn't supported on strokes and keeps the stroke
  /// color of the context.
  package let color: CGColor?
  /// The dashes, or `nil` if none of them has a length.
  package let dashes: [CGFloat]?
  package let dashOffset: CGFloat
  package let width: CGFloat
  package let cap: CGLineCap
  package let join: CGLineJoin
  package let miterLimit: CGFloat
}

package enum MaskApplication: Sendable {
  case none
  /// A line that has a mask and no area clips everything.
  case clipToZero
  case mask(MaskEffect)
}

package struct GroupNode: Sendable {
  package let id: RenderID
  package let transform: CGAffineTransform
  package let opacity: CGFloat
  package let clip: ClipPathEffect?
  package let children: [RenderNode]
}

package struct ViewportNode: Sendable {
  package let id: RenderID
  /// The translation by `x` and `y`.
  package let translation: CGAffineTransform
  /// The content, or `nil` if the viewport has no area.
  package let content: ViewportContent?
}

package struct ViewportContent: Sendable {
  package let viewBoxTransform: CGAffineTransform
  package let overflowClip: CGRect?
  package let clip: ClipPathEffect?
  package let children: [RenderNode]
}

package struct UseNode: Sendable {
  package let id: RenderID
  package let transform: CGAffineTransform
  package let clip: ClipPathEffect?
  /// The referenced content, or `nil` if there is none or showing it would make a cycle.
  package let instance: UseInstance?
}

package struct UseInstance: Sendable {
  /// The translation by `x` and `y`.
  package let translation: CGAffineTransform
  package let opacity: CGFloat
  package let content: RenderNode?
}
