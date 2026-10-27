import CoreGraphics
import Foundation
import SVGCore

/// Plans the layers that a render tree is rendered into.
///
/// Each node of an element whose transform or opacity is animated gets a container layer of its own, with the
/// transform and the opacity, so that a change of them changes only the layer. The nodes between them are painted
/// together into the contents of a layer, in the order of the render tree, so that the layers show what painting the
/// whole tree into one bitmap shows.
///
/// A node with a clip path, a mask or a filter composites what it paints as one image, so the nodes in it are painted
/// with it, and none of them gets a layer of its own.
package struct LayerPlanner: Sendable {
  /// The elements whose nodes get layers of their own.
  let promoted: Set<ElementID>
  /// The scale of the screen.
  let scale: CGFloat

  /// The width in pixels of the margin around what a layer paints, for the antialiased edges of the shapes.
  private static let margin: CGFloat = 2

  package init(promoted: Set<ElementID>, scale: CGFloat) {
    self.promoted = promoted
    self.scale = scale
  }

  /// The layers that show the render tree in a rectangle, inside a layer that clips them to it.
  ///
  /// - Parameter rect: The rectangle that the tree is rendered into, in the coordinates of the layer around the
  ///   returned one.
  package func plan(_ tree: RenderTree, in rect: CGRect) -> ContainerLayer {
    // The root transforms apply one after another, so the last one maps to the rectangle.
    let fit = tree.rootTransforms.reversed().reduce(CGAffineTransform.identity) { $0.concatenating($1) }
    let context = Context(transform: fit, view: rect, isFixed: true)
    let content = ContainerLayer(
      id: nil, transform: fit, opacity: 1, clip: nil,
      children: tree.root.map { layers(of: [$0], in: context) } ?? [])
    return ContainerLayer(id: nil, transform: .identity, opacity: 1, clip: rect, children: [.container(content)])
  }

  /// Where the layers of some nodes are.
  private struct Context {
    /// The transform from the coordinates of the nodes to the coordinates of the view.
    let transform: CGAffineTransform
    /// The rectangle of the view in its coordinates.
    let view: CGRect
    /// Whether no animation moves the nodes in the view, so that what's outside the view never shows.
    let isFixed: Bool

    func inside(_ transform: CGAffineTransform, isFixed: Bool = true) -> Context {
      Context(transform: transform.concatenating(self.transform), view: view, isFixed: self.isFixed && isFixed)
    }
  }

  /// The layers of nodes in order: a painted layer for each run of nodes without layers of their own, and the
  /// layers of the other nodes between them.
  private func layers(of nodes: [RenderNode], in context: Context) -> [PlannedLayer] {
    var layers = [PlannedLayer]()
    var run = [RenderNode]()
    func paintRun() {
      if let layer = painted(run, in: context) {
        layers.append(.painted(layer))
      }
      run = []
    }
    for node in nodes {
      if let layer = container(of: node, in: context) {
        paintRun()
        layers.append(.container(layer))
      } else {
        run.append(node)
      }
    }
    paintRun()
    return layers
  }

  /// The container layer of a node, or `nil` if the node is painted with the nodes around it: when neither it nor a
  /// node in it gets a layer of its own.
  private func container(of node: RenderNode, in context: Context) -> ContainerLayer? {
    let isPromoted = promoted.contains(node.id.element)
    guard isPromoted || containsPromoted(node) else { return nil }
    // An animation moves what the layer of a promoted node shows.
    let isFixed = !isPromoted
    switch node {
    case .group(let group) where group.clip == nil && group.mask == nil:
      let inner = context.inside(group.transform, isFixed: isFixed)
      return ContainerLayer(
        id: group.id, transform: group.transform, opacity: group.opacity, clip: nil,
        children: layers(of: group.children, in: inner))
    case .use(let use) where use.clip == nil && use.mask == nil:
      let transform = (use.instance?.translation ?? .identity).concatenating(use.transform)
      let inner = context.inside(transform, isFixed: isFixed)
      return ContainerLayer(
        id: use.id, transform: transform, opacity: use.instance?.opacity ?? 1, clip: nil,
        children: use.instance?.content.map { layers(of: [$0], in: inner) } ?? [])
    case .viewport(let viewport) where viewport.content.map({ $0.clip == nil && $0.mask == nil }) ?? true:
      guard let content = viewport.content else { return nil }
      let transform = content.viewBoxTransform.concatenating(viewport.translation).concatenating(viewport.transform)
      let inner = context.inside(transform, isFixed: isFixed)
      let children = layers(of: content.children, in: inner)
      // The overflow of a viewport is clipped in the coordinates of its content.
      let clipped =
        content.overflowClip.map {
          [PlannedLayer.container(ContainerLayer(id: nil, transform: .identity, opacity: 1, clip: $0, children: children))]
        } ?? children
      return ContainerLayer(id: viewport.id, transform: transform, opacity: 1, clip: nil, children: clipped)
    default:
      // A promoted node that paints as one image, or a shape, is painted in its own coordinates in its layer.
      let inner = context.inside(node.transform, isFixed: false)
      return ContainerLayer(
        id: node.id, transform: node.transform, opacity: node.groupOpacity, clip: nil,
        children: painted([node.withoutCompositing], in: inner).map { [.painted($0)] } ?? [])
    }
  }

  /// Whether a node in the node gets a layer of its own, which it doesn't inside a node that composites what it
  /// paints as one image.
  private func containsPromoted(_ node: RenderNode) -> Bool {
    func isOrContainsPromoted(_ node: RenderNode) -> Bool {
      promoted.contains(node.id.element) || containsPromoted(node)
    }
    switch node {
    case .group(let group):
      return group.clip == nil && group.mask == nil && group.children.contains(where: isOrContainsPromoted)
    case .use(let use):
      guard use.clip == nil, use.mask == nil, let content = use.instance?.content else { return false }
      return isOrContainsPromoted(content)
    case .viewport(let viewport):
      guard let content = viewport.content, content.clip == nil, content.mask == nil else { return false }
      return content.children.contains(where: isOrContainsPromoted)
    case .shape, .filtered:
      return false
    }
  }

  /// The painted layer of nodes, or `nil` if they paint nothing that can show.
  private func painted(_ nodes: [RenderNode], in context: Context) -> PaintedLayer? {
    guard !nodes.isEmpty else { return nil }
    let transform = context.transform
    let rasterScale = scale * max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
    guard rasterScale > 0, rasterScale.isFinite else { return nil }
    var bounds = nodes.paintedBounds
    if context.isFixed {
      // What's outside the view never shows, so the contents don't cover it.
      bounds = bounds.intersection(context.view.applying(transform.inverted()))
    }
    guard !bounds.isNull, !bounds.isEmpty else { return nil }
    let margin = Self.margin / rasterScale
    bounds = bounds.insetBy(dx: -margin, dy: -margin)
    if transform.b == 0, transform.c == 0, abs(transform.a) == abs(transform.d) {
      // Without a rotation, a skew or a scale that differs between the axes, the pixels of the contents can lie on
      // the pixels of the screen, so that the layer shows the same pixels as a rendering into one bitmap. A flip
      // keeps them there.
      let pixels = CGAffineTransform(scaleX: scale, y: scale)
      let device = bounds.applying(transform.concatenating(pixels)).integral
      bounds = device.applying(transform.concatenating(pixels).inverted())
    }
    return PaintedLayer(nodes: nodes, bounds: bounds, rasterScale: rasterScale)
  }
}
