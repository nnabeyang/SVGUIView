import CoreGraphics
import Foundation
import SVGCore

extension RenderNode {
  /// A rectangle in the coordinates of the parent of the node that contains everything the node paints, or
  /// `CGRect.null` for a node that paints nothing.
  ///
  /// The rectangle can be larger than what the node paints: a stroke counts as if it had no dashes, and the
  /// antialiased edges of the shapes aren't counted, so a layer adds a margin to it.
  package var paintedBounds: CGRect {
    switch self {
    case .shape(let shape):
      shape.paintedBounds
    case .group(let group):
      group.children.paintedBounds.clipped(by: group.clip, group.mask).applying(group.transform)
    case .viewport(let viewport):
      viewport.paintedBounds
    case .use(let use):
      (use.instance?.content?.paintedBounds ?? .null).applying(use.instance?.translation ?? .identity)
        .clipped(by: use.clip, use.mask).applying(use.transform)
    case .filtered(let filtered):
      filtered.effectRect.applying(filtered.transform)
    }
  }
}

extension [RenderNode] {
  /// A rectangle that contains everything the nodes paint, in the coordinates of their parent.
  package var paintedBounds: CGRect {
    reduce(.null) { $0.union($1.paintedBounds) }
  }
}

extension ShapeNode {
  fileprivate var paintedBounds: CGRect {
    guard let geometry, let content else { return .null }
    let path = geometry.path.cgPath
    // The frame of text is the bounds of its lines, and the frame of an image is where it's drawn.
    var bounds = geometry.frame.union(path.boundingBoxOfPath)
    let stroke: StrokeStyle? =
      switch content {
      case .vector(_, let stroke, _): stroke
      case .image(_, let stroke): stroke
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
  fileprivate var paintedBounds: CGRect {
    guard let content else { return .null }
    var bounds = content.children.paintedBounds
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
