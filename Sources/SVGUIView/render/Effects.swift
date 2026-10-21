import CoreGraphics
import Foundation

/// A clip path, built for the bounds of the element that it clips.
///
/// The shapes are drawn into a bitmap of the bounds, whose alpha clips the element.
final class ClipPathEffect: Sendable {
  /// The bounds of the element, which the bitmap covers.
  let frame: CGRect
  /// The `transform` of the `<clipPath>` element.
  let transform: CGAffineTransform
  let units: SVGUnitType
  let shapes: [ClipShape]
  /// The clip path of the `<clipPath>` element. It clips what the element is drawn into, rather than the shapes,
  /// after they're drawn (svg_ui_view-90).
  let clipPath: ClipPathEffect?

  init(frame: CGRect, transform: CGAffineTransform, units: SVGUnitType, shapes: [ClipShape], clipPath: ClipPathEffect?) {
    self.frame = frame
    self.transform = transform
    self.units = units
    self.shapes = shapes
    self.clipPath = clipPath
  }
}

/// A child of a `<clipPath>` element.
struct ClipShape: Sendable {
  let path: RenderPath
  let transform: CGAffineTransform
  /// The clip path of the child, built for the bounds of the clipped element.
  let clip: ClipPathEffect?
  let fillRule: CGPathDrawingMode
}

/// A mask, built for the bounds of the element that it masks.
///
/// The content is drawn into a bitmap of the bounds, whose luminance masks the element.
final class MaskEffect: Sendable {
  /// The bounds of the element, which the bitmap covers.
  let frame: CGRect
  /// The rectangle of `x`, `y`, `width` and `height`, which clips the element too.
  let region: CGRect
  let contentUnits: SVGUnitType
  let colorInterpolation: SVGColorInterpolation
  let contents: [MaskContent]
  /// The clip path of the `<mask>` element, which clips the bitmap after the content is drawn
  /// (svg_ui_view-90).
  let clipPath: ClipPathEffect?

  init(
    frame: CGRect, region: CGRect, contentUnits: SVGUnitType, colorInterpolation: SVGColorInterpolation,
    contents: [MaskContent], clipPath: ClipPathEffect?
  ) {
    self.frame = frame
    self.region = region
    self.contentUnits = contentUnits
    self.colorInterpolation = colorInterpolation
    self.contents = contents
    self.clipPath = clipPath
  }
}

/// A child of a `<mask>` element, which paints its fill and no stroke.
struct MaskContent: Sendable {
  let path: RenderPath
  let transform: CGAffineTransform
  /// The clip path of the child, built for the bounds of the masked element.
  let clip: ClipPathEffect?
  /// The mask of the child, built for the bounds of the masked element.
  let mask: MaskEffect?
  /// The fill, without a stroke.
  let fill: ShapeContent
}

/// A pattern, built for the element that it fills.
///
/// The content is drawn into a bitmap of a tile, which is repeated from the position of the pattern.
final class PatternPaint: Sendable {
  /// The opacity of the fill.
  let opacity: CGFloat
  /// The size of the tile, scaled by the scale of `patternTransform`.
  let tileSize: CGSize
  /// The `patternTransform` of the `<pattern>` element.
  let transform: CGAffineTransform
  /// The position of the tile, in the user space of the element.
  let origin: CGPoint
  /// The bounds of the element.
  let frame: CGRect
  /// The transform of the `viewBox` of the `<pattern>` element into the tile.
  let viewBoxTransform: CGAffineTransform?
  let colorInterpolation: SVGColorInterpolation
  let content: [RenderNode]
  /// The clip path of the `<pattern>` element, which clips the tile after the content is drawn (svg_ui_view-90).
  let clipPath: ClipPathEffect?

  init(
    opacity: CGFloat, tileSize: CGSize, transform: CGAffineTransform, origin: CGPoint, frame: CGRect,
    viewBoxTransform: CGAffineTransform?, colorInterpolation: SVGColorInterpolation, content: [RenderNode],
    clipPath: ClipPathEffect?
  ) {
    self.opacity = opacity
    self.tileSize = tileSize
    self.transform = transform
    self.origin = origin
    self.frame = frame
    self.viewBoxTransform = viewBoxTransform
    self.colorInterpolation = colorInterpolation
    self.content = content
    self.clipPath = clipPath
  }
}
