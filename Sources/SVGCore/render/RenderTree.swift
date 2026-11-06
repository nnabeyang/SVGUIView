import CoreGraphics
import CoreText
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
  /// The nodes of elements that make the same nodes at every time, which the render tree of the document at another
  /// time can reuse.
  package var reusableNodes = RenderNodeCache()
}

/// Nodes of a render tree by the elements and the modes that they're made for.
package struct RenderNodeCache: Sendable {
  struct Key: Hashable, Sendable {
    let id: RenderID
    let mode: DrawMode
  }

  var nodes = [Key: RenderNode]()

  package init() {}
}

/// Collects the nodes that a render tree reuses or makes, while a builder makes it in one task.
final class RenderNodeCollector {
  var cache = RenderNodeCache()
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
  /// Whether the edges of what the shape paints are antialiased, which `shape-rendering` turns off for shapes.
  package var antialiases = true
  /// How the shape blends with what's behind it in its isolation group.
  package var blendMode = CGBlendMode.normal
  /// Whether the shape paints colors outside sRGB, which a bitmap of a wide gamut shows.
  package let usesWideGamut: Bool

  package init(
    id: RenderID, transform: CGAffineTransform, geometry: Geometry?, clip: ClipPathEffect?, mask: MaskApplication,
    opacity: CGFloat, content: ShapeContent?, antialiases: Bool = true, blendMode: CGBlendMode = .normal
  ) {
    self.id = id
    self.transform = transform
    self.geometry = geometry
    self.clip = clip
    self.mask = mask
    self.opacity = opacity
    self.content = content
    self.antialiases = antialiases
    self.blendMode = blendMode
    usesWideGamut = content?.usesWideGamut ?? false
  }
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
  case image(ImagePaint?, stroke: StrokeStyle?)
  /// Glyphs that are drawn in their own colors, such as emoji, with the opacity of the fill.
  case colorGlyphs([ColorGlyph], opacity: CGFloat)
}

/// A glyph that a font draws in its own colors, such as an emoji of Apple Color Emoji, which has no outline to fill.
/// The font is immutable, which Core Text doesn't mark `Sendable`.
package struct ColorGlyph: @unchecked Sendable {
  package let font: CTFont
  package let glyph: CGGlyph
  /// The transform from the coordinates of the font, with the origin at the origin of the glyph, to the user space.
  package let transform: CGAffineTransform

  /// The bounds of the glyph in the user space.
  var bounds: CGRect {
    var glyph = glyph
    var rect = CGRect.zero
    CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &rect, 1)
    return rect.applying(transform)
  }
}

/// An image placed in the rectangle of its element by its `preserveAspectRatio`.
package struct ImagePaint: Sendable {
  package let content: ImageContent
  /// Where the image is drawn, in the coordinates of its element: the bitmap, or the view box of the SVG image.
  package let rect: CGRect
  /// The rectangle of the element, which clips the image where its overflow is hidden and the image overflows it,
  /// or `nil` if nothing clips it.
  package let clip: CGRect?
  /// Whether a bitmap is interpolated where it's scaled, which `image-rendering` decides. An SVG image is drawn as
  /// shapes, which it doesn't apply to.
  package var interpolates = true
}

/// What an image is drawn from.
package enum ImageContent: Sendable {
  /// A bitmap, which is drawn in the rectangle of its paint.
  case bitmap(CGImage)
  /// The node of the root element of an SVG image, which places the image in the rectangle of its element.
  case document(RenderNode)
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
  /// What the stroke is painted with: a color, or a gradient or a pattern, which paints the outline of the stroke.
  package let paint: FillPaint
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
  package let mask: MaskEffect?
  package let children: [RenderNode]
  /// Whether the children paint colors outside sRGB, which a bitmap of a wide gamut shows.
  package let usesWideGamut: Bool
  /// How the group blends with what's behind it in its isolation group.
  package var blendMode = CGBlendMode.normal
  /// Whether the group is an isolation group, which what it contains blends in, though nothing else makes it one.
  package var isolates = false

  package init(
    id: RenderID, transform: CGAffineTransform, opacity: CGFloat, clip: ClipPathEffect?, mask: MaskEffect?,
    children: [RenderNode], blendMode: CGBlendMode = .normal, isolates: Bool = false
  ) {
    self.id = id
    self.transform = transform
    self.opacity = opacity
    self.clip = clip
    self.mask = mask
    self.children = children
    self.blendMode = blendMode
    self.isolates = isolates
    usesWideGamut = children.contains(where: \.usesWideGamut)
  }
}

package struct ViewportNode: Sendable {
  package let id: RenderID
  /// The transform of the element, which applies before the translation.
  package let transform: CGAffineTransform
  /// The translation by `x` and `y`.
  package let translation: CGAffineTransform
  /// The opacity that the content is composited with, after the overflow is clipped and the mask applies.
  package let opacity: CGFloat
  /// The content, or `nil` if the viewport has no area.
  package let content: ViewportContent?
  /// How the viewport blends with what's behind it in its isolation group.
  package var blendMode = CGBlendMode.normal
  /// Whether the viewport is an isolation group, though nothing else makes it one.
  package var isolates = false
}

package struct ViewportContent: Sendable {
  package let viewBoxTransform: CGAffineTransform
  package let overflowClip: CGRect?
  package let clip: ClipPathEffect?
  package let mask: MaskEffect?
  package let children: [RenderNode]
  /// Whether the children paint colors outside sRGB, which a bitmap of a wide gamut shows.
  package let usesWideGamut: Bool

  package init(
    viewBoxTransform: CGAffineTransform, overflowClip: CGRect?, clip: ClipPathEffect?, mask: MaskEffect?,
    children: [RenderNode]
  ) {
    self.viewBoxTransform = viewBoxTransform
    self.overflowClip = overflowClip
    self.clip = clip
    self.mask = mask
    self.children = children
    usesWideGamut = children.contains(where: \.usesWideGamut)
  }
}

package struct UseNode: Sendable {
  package let id: RenderID
  package let transform: CGAffineTransform
  package let clip: ClipPathEffect?
  package let mask: MaskEffect?
  /// The referenced content, or `nil` if there is none or showing it would make a cycle.
  package let instance: UseInstance?
  /// How the element blends with what's behind it in its isolation group.
  package var blendMode = CGBlendMode.normal
  /// Whether the element is an isolation group, though nothing else makes it one.
  package var isolates = false
}

package struct UseInstance: Sendable {
  /// The translation by `x` and `y`.
  package let translation: CGAffineTransform
  package let opacity: CGFloat
  package let content: RenderNode?
  /// Whether the content paints colors outside sRGB, which a bitmap of a wide gamut shows.
  package let usesWideGamut: Bool

  package init(translation: CGAffineTransform, opacity: CGFloat, content: RenderNode?) {
    self.translation = translation
    self.opacity = opacity
    self.content = content
    usesWideGamut = content?.usesWideGamut ?? false
  }
}
