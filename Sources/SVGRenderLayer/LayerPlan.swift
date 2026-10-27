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
  package let children: [PlannedLayer]
}

/// Render nodes that are painted together into the contents of a layer.
package struct PaintedLayer: Sendable {
  /// The nodes in the order that they're painted, in the coordinates of the layer around this one.
  package let nodes: [RenderNode]
  /// The rectangle that the nodes paint in, in the coordinates of the layer around this one, which the contents
  /// cover.
  package let bounds: CGRect
  /// The pixels of the contents for each unit of the coordinates, which is the scale of the screen times the scale of
  /// the transforms around the layer, so that the contents are as sharp as a rendering into one bitmap.
  package let rasterScale: CGFloat
}
