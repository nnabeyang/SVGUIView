import CoreGraphics
import Foundation

/// A clip path, built for the bounds of the element that it clips.
///
/// The shapes are drawn into a bitmap of their region, whose alpha clips the element.
package final class ClipPathEffect: Sendable {
  /// The bounds of the element, which the units of the shapes are fractions of.
  package let frame: CGRect
  /// The `transform` of the `<clipPath>` element.
  package let transform: CGAffineTransform
  package let units: SVGUnitType
  package let shapes: [ClipShape]
  /// The clip path of the `<clipPath>` element, which clips the shapes in the user space of the element.
  package let clipPath: ClipPathEffect?

  init(frame: CGRect, transform: CGAffineTransform, units: SVGUnitType, shapes: [ClipShape], clipPath: ClipPathEffect?) {
    self.frame = frame
    self.transform = transform
    self.units = units
    self.shapes = shapes
    self.clipPath = clipPath
  }

  /// The bounds of the shapes in the user space of the clipped element, which the clip path covers, so that what the
  /// element draws outside its bounds, such as its markers, is clipped as the shapes clip it.
  package var region: CGRect {
    let units: CGAffineTransform =
      switch self.units {
      case .userSpaceOnUse: .identity
      case .objectBoundingBox:
        CGAffineTransform(a: frame.width, b: 0, c: 0, d: frame.height, tx: frame.minX, ty: frame.minY)
      }
    let space = units.concatenating(transform)
    var region = CGRect.null
    for shape in shapes {
      region = region.union(shape.path.cgPath.boundingBoxOfPath.applying(shape.transform.concatenating(space)))
    }
    if let clipPath {
      region = region.intersection(clipPath.region)
    }
    return region
  }
}

/// A child of a `<clipPath>` element.
package struct ClipShape: Sendable {
  package let path: RenderPath
  package let transform: CGAffineTransform
  /// The clip path of the child, built for the bounds of the clipped element.
  package let clip: ClipPathEffect?
  package let fillRule: CGPathDrawingMode
}

/// A mask, built for the bounds of the element that it masks.
///
/// The content is drawn into a bitmap of the region, whose luminance masks the element.
package final class MaskEffect: Sendable {
  /// The bounds of the element, which the units of the content are fractions of.
  package let frame: CGRect
  /// The rectangle of `x`, `y`, `width` and `height`, which clips the element too, and the bitmap covers.
  package let region: CGRect
  package let contentUnits: SVGUnitType
  package let colorInterpolation: SVGColorInterpolation
  /// The nodes of the children of the `<mask>` element, in the units of its content.
  package let contents: [RenderNode]

  init(
    frame: CGRect, region: CGRect, contentUnits: SVGUnitType,
    colorInterpolation: SVGColorInterpolation, contents: [RenderNode]
  ) {
    self.frame = frame
    self.region = region
    self.contentUnits = contentUnits
    self.colorInterpolation = colorInterpolation
    self.contents = contents
  }
}

/// A pattern, built for the element that it fills.
///
/// The content is drawn into a bitmap of a tile, which is repeated from the position of the pattern.
package final class PatternPaint: Sendable {
  /// The opacity of the fill.
  package let opacity: CGFloat
  /// The size of the tile, scaled by the scale of `patternTransform`.
  package let tileSize: CGSize
  /// The `patternTransform` of the `<pattern>` element.
  package let transform: CGAffineTransform
  /// The position of the tile, in the user space of the element.
  package let origin: CGPoint
  /// The bounds of the element.
  package let frame: CGRect
  /// The transform of the `viewBox` of the `<pattern>` element into the tile.
  package let viewBoxTransform: CGAffineTransform?
  package let colorInterpolation: SVGColorInterpolation
  package let content: [RenderNode]

  init(
    opacity: CGFloat, tileSize: CGSize, transform: CGAffineTransform, origin: CGPoint, frame: CGRect,
    viewBoxTransform: CGAffineTransform?, colorInterpolation: SVGColorInterpolation, content: [RenderNode]
  ) {
    self.opacity = opacity
    self.tileSize = tileSize
    self.transform = transform
    self.origin = origin
    self.frame = frame
    self.viewBoxTransform = viewBoxTransform
    self.colorInterpolation = colorInterpolation
    self.content = content
  }
}
