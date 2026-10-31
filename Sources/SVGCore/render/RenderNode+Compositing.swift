import CoreGraphics
import Foundation

extension RenderNode {
  /// The identity of the node.
  package var id: RenderID {
    switch self {
    case .shape(let shape): shape.id
    case .group(let group): group.id
    case .viewport(let viewport): viewport.id
    case .use(let use): use.id
    case .filtered(let filtered): filtered.id
    }
  }

  /// The transform of the node, from its coordinates to the coordinates of its parent.
  package var transform: CGAffineTransform {
    switch self {
    case .shape(let shape): shape.transform
    case .group(let group): group.transform
    case .viewport(let viewport): viewport.transform
    case .use(let use): use.transform
    case .filtered(let filtered): filtered.transform
    }
  }

  /// The opacity that the node composites what it paints with as a group, which a layer can apply instead: the
  /// opacity of a shape, a group or a viewport, and of the content of a `<use>`. A filtered node draws each
  /// primitive with its opacity, so its opacity is 1.
  package var groupOpacity: CGFloat {
    switch self {
    case .shape(let shape): shape.opacity
    case .group(let group): group.opacity
    case .viewport(let viewport): viewport.opacity
    case .use(let use): use.instance?.opacity ?? 1
    case .filtered: 1
    }
  }

  /// How the node blends with what's behind it in its isolation group.
  package var blendMode: CGBlendMode {
    switch self {
    case .shape(let shape): shape.blendMode
    case .group(let group): group.blendMode
    case .viewport(let viewport): viewport.blendMode
    case .use(let use): use.blendMode
    case .filtered(let filtered): filtered.blendMode
    }
  }

  /// The node without its transform and its group opacity, which paints in its own coordinates what a layer with
  /// the transform and the opacity composites.
  package var withoutCompositing: RenderNode {
    switch self {
    case .shape(let shape):
      .shape(
        ShapeNode(
          id: shape.id, transform: .identity, geometry: shape.geometry, clip: shape.clip, mask: shape.mask, opacity: 1,
          content: shape.content, antialiases: shape.antialiases))
    case .group(let group):
      .group(
        GroupNode(
          id: group.id, transform: .identity, opacity: 1, clip: group.clip, mask: group.mask, children: group.children))
    case .viewport(let viewport):
      .viewport(
        ViewportNode(
          id: viewport.id, transform: .identity, translation: viewport.translation, opacity: 1,
          content: viewport.content))
    case .use(let use):
      .use(
        UseNode(
          id: use.id, transform: .identity, clip: use.clip, mask: use.mask,
          instance: use.instance.map { UseInstance(translation: $0.translation, opacity: 1, content: $0.content) }))
    case .filtered(let filtered):
      .filtered(
        FilteredNode(
          id: filtered.id, transform: .identity, frame: filtered.frame, effectRect: filtered.effectRect,
          colorInterpolation: filtered.colorInterpolation, colorInterpolationFilters: filtered.colorInterpolationFilters,
          opacity: filtered.opacity, primitives: filtered.primitives, source: filtered.source))
    }
  }
}
