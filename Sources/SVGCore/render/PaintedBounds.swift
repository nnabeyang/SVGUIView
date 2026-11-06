import CoreGraphics
import Foundation

extension RenderNode {
  /// A rectangle in the coordinates of the parent of the node that contains everything the node paints, or
  /// `CGRect.null` for a node that paints nothing.
  ///
  /// The rectangle can be larger than what the node paints: a stroke counts as if it had no dashes, and the
  /// antialiased edges of the shapes aren't counted, so a layer adds a margin to it.
  package var paintedBounds: CGRect {
    paintedBounds(filtersWithin: nil)
  }

  /// A rectangle that contains everything the node paints, with its filter regions and the ones of its descendants
  /// limited to a rectangle in the coordinates of the parent, as the painting limits a huge filter region to what
  /// shows, or not limited for `nil`.
  package func paintedBounds(filtersWithin limit: CGRect?) -> CGRect {
    /// The limit in the coordinates inside a transform, or none if the transform has no inverse.
    func inside(_ transform: CGAffineTransform) -> CGRect? {
      guard let limit, transform.isInvertible else { return nil }
      return limit.applying(transform.inverted())
    }
    switch self {
    case .shape(let shape):
      return shape.paintedBounds
    case .group(let group):
      return group.children.paintedBounds(filtersWithin: inside(group.transform)).clipped(by: group.clip, group.mask)
        .applying(group.transform)
    case .viewport(let viewport):
      return viewport.paintedBounds(filtersWithin: limit)
    case .use(let use):
      let translation = use.instance?.translation ?? .identity
      let content =
        use.instance?.content?.paintedBounds(filtersWithin: inside(translation.concatenating(use.transform))) ?? .null
      return content.applying(translation).clipped(by: use.clip, use.mask).applying(use.transform)
    case .filtered(let filtered):
      let region = inside(filtered.transform).map(filtered.effectRect.intersection) ?? filtered.effectRect
      return region.applying(filtered.transform)
    }
  }
}

extension [RenderNode] {
  /// A rectangle that contains everything the nodes paint, in the coordinates of their parent.
  package var paintedBounds: CGRect {
    paintedBounds(filtersWithin: nil)
  }

  /// A rectangle that contains everything the nodes paint, with their filter regions limited to a rectangle in the
  /// coordinates of their parent, or not limited for `nil`.
  package func paintedBounds(filtersWithin limit: CGRect?) -> CGRect {
    reduce(.null) { $0.union($1.paintedBounds(filtersWithin: limit)) }
  }
}

extension ShapeNode {
  fileprivate var paintedBounds: CGRect {
    guard let geometry, let content else { return .null }
    let path = geometry.path.cgPath
    // The frame of text is the bounds of its lines.
    var bounds = geometry.frame.union(path.boundingBoxOfPath)
    // An image is drawn where it's placed, which can be outside the rectangle of its element. Matching it apart from
    // the stroke keeps the other shapes as fast as before, as the layers compute the bounds of every shape each frame.
    if case .image(let image?, _) = content {
      bounds = bounds.union(image.clip.map(image.rect.intersection) ?? image.rect)
    }
    let stroke: StrokeStyle? =
      switch content {
      case .vector(_, let stroke, _): stroke
      case .image(_, let stroke): stroke
      case .colorGlyphs: nil
      }
    if let stroke, stroke.width > 0 {
      let stroked = path.copy(
        strokingWithWidth: stroke.width, lineCap: stroke.cap, lineJoin: stroke.join, miterLimit: stroke.miterLimit)
      bounds = bounds.union(stroked.boundingBoxOfPath).union(geometry.frame.insetBy(dx: -stroke.width / 2, dy: -stroke.width / 2))
    }
    let clipped: CGRect =
      switch mask {
      case .none: bounds.clipped(by: clip, nil)
      case .clipToZero: .null
      case .mask(let mask): bounds.clipped(by: clip, mask)
      }
    return clipped.applying(transform)
  }
}

extension ViewportNode {
  fileprivate func paintedBounds(filtersWithin limit: CGRect?) -> CGRect {
    guard let content else { return .null }
    let outside = content.viewBoxTransform.concatenating(translation).concatenating(transform)
    let inner = limit.flatMap { outside.isInvertible ? $0.applying(outside.inverted()) : nil }
    var bounds = content.children.paintedBounds(filtersWithin: inner)
    if let overflowClip = content.overflowClip {
      bounds = bounds.intersection(overflowClip)
    }
    return bounds.clipped(by: content.clip, content.mask).applying(content.viewBoxTransform).applying(translation)
      .applying(transform)
  }
}

extension CGRect {
  /// The rectangle without what a clip path and a mask leave out, which is everything outside the bounds of the
  /// clip path, and outside the bounds and the region of the mask.
  fileprivate func clipped(by clip: ClipPathEffect?, _ mask: MaskEffect?) -> CGRect {
    var rect = self
    if let clip {
      rect = rect.intersection(clip.frame)
    }
    if let mask {
      rect = rect.intersection(mask.frame).intersection(mask.region)
    }
    return rect
  }
}
