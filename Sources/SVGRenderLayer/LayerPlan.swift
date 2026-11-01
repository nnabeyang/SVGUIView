import CoreGraphics
import Foundation
import SVGCore

/// A layer of the layers that a render tree is rendered into, before the layers are made.
package indirect enum PlannedLayer: Sendable {
  /// A layer that only transforms, fades and clips the layers in it, which is what animations of the transform and
  /// the opacity of an element change.
  case container(ContainerLayer)
  /// A layer whose contents are render nodes painted together.
  case painted(PaintedLayer)
}

/// A layer that transforms, fades and clips the layers in it, in order.
package struct ContainerLayer: Sendable {
  /// The node that the layer composites, or `nil` for a layer that doesn't come from one, such as the one that clips
  /// the content of a viewport.
  package let id: RenderID?
  /// The transform from the coordinates of the layer to the coordinates of the layer around it.
  package let transform: CGAffineTransform
  /// The opacity that the layers in it are composited together with.
  package let opacity: CGFloat
  /// The rectangle in the coordinates of the layer outside which nothing is shown, or `nil` to show everything.
  package let clip: CGRect?
  /// The clip of a viewport whose edges lie between the pixels of the screen, which the layers in it are composited
  /// together and then clipped by, or `nil`.
  package let mask: ClipMask?
  package let children: [PlannedLayer]
  /// What the layer is in the plans of all times.
  package let key: LayerKey
}

/// The clip of a viewport, which applies once to what the layers in it show composited together, with the coverage of
/// the pixels at its edges that a rendering into one bitmap gives them.
///
/// A layer that masks to its bounds clips at the pixels of the screen, without the coverage of the pixels that its
/// edges cross, so a clip whose edges lie between the pixels clips by an image of its coverage instead.
package struct ClipMask: Sendable {
  /// The rectangle of the clip, in the coordinates of the container.
  package let clip: CGRect
  /// The rectangle that the image covers: the clip grown to the pixels of the screen that it covers.
  package let bounds: CGRect
  /// The pixels of the image for each unit of the coordinates along each axis.
  package let rasterScale: CGSize
  /// What the mask is in the plans of all times.
  package let key: LayerKey
}

/// Render nodes that are painted together into the contents of a layer.
package struct PaintedLayer: Sendable {
  /// The nodes in the order that they're painted, in the coordinates of the layer around this one.
  package let nodes: [RenderNode]
  /// The rectangle that the nodes paint in, in the coordinates of the layer around this one, which the contents
  /// cover.
  package let bounds: CGRect
  /// The pixels of the contents for each unit of the coordinates along each axis, which is the scale of the screen
  /// times the scale of the transforms around the layer along the axis, so that the contents are as sharp as a
  /// rendering into one bitmap, also under a transform that scales the axes differently.
  package let rasterScale: CGSize
  /// The rectangle of the view in the coordinates of the layer around this one, which the contents are clipped to,
  /// or `nil` for a layer that an animation moves.
  package let view: CGRect?
  /// Whether what the nodes paint can change with the time, so that the contents of another time can't be shown.
  package let changes: Bool
  /// What the layer is in the plans of all times, which the layers of one time are matched with the layers of
  /// another by.
  package let key: LayerKey
}

/// What a layer is in the plans of a render tree at all times: the containers around it, and for a painted layer, the
/// nodes that it paints.
package struct LayerKey: Hashable, Sendable {
  package enum Component: Hashable, Sendable {
    /// A container of a node.
    case node(RenderID)
    /// A container that doesn't come from a node, at an index of the layers around it.
    case index(Int)
    /// The nodes of a painted layer.
    case nodes([RenderID])
  }

  package let components: [Component]

  func appending(_ component: Component) -> LayerKey {
    LayerKey(components: components + [component])
  }
}
