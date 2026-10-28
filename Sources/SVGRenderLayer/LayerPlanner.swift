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
/// A node with a filter whose painting changes with the time, such as by an animation of the values of its
/// primitives or of the nodes that it filters, is painted into a layer of its own, so that the nodes around it aren't
/// painted again with it.
///
/// A node with a clip path, a mask or a filter composites what it paints as one image, so the nodes in it are painted
/// with it, and none of them gets a layer of its own.
///
/// A painted layer whose nodes don't change with the time can show the contents of another time.
package struct LayerPlanner: Sendable {
  /// The elements whose nodes get layers of their own, which are the ones whose compositing is animated.
  let promoted: Set<ElementID>
  /// The elements whose painting changes in other ways, or `nil` if any painting can change.
  let painting: Set<ElementID>?
  /// The scale of the screen.
  let scale: CGFloat

  /// The width in pixels of the margin around what a layer paints, for the antialiased edges of the shapes.
  private static let margin: CGFloat = 2

  /// - Parameters:
  ///   - promoted: The elements whose compositing is animated, which get layers of their own.
  ///   - painting: The elements whose painting changes in other ways, or `nil` if any painting can change.
  package init(promoted: Set<ElementID>, painting: Set<ElementID>? = nil, scale: CGFloat) {
    self.promoted = promoted
    self.painting = painting
    self.scale = scale
  }

  /// The layers that show the render tree in a rectangle, inside a layer that clips them to it.
  ///
  /// - Parameter rect: The rectangle that the tree is rendered into, in the coordinates of the layer around the
  ///   returned one.
  package func plan(_ tree: RenderTree, in rect: CGRect) -> ContainerLayer {
    // The root transforms apply one after another, so the last one maps to the rectangle.
    let fit = tree.rootTransforms.reversed().reduce(CGAffineTransform.identity) { $0.concatenating($1) }
    let context = Context(
      transform: fit, restingTransform: fit, view: rect, isFixed: true, isChanging: false,
      key: LayerKey(components: [.index(0), .index(0)]))
    let content = ContainerLayer(
      id: nil, transform: fit, opacity: 1, clip: nil,
      children: tree.root.map { layers(of: [$0], in: context) } ?? [], key: context.key)
    return ContainerLayer(
      id: nil, transform: .identity, opacity: 1, clip: rect, children: [.container(content)],
      key: LayerKey(components: [.index(0)]))
  }

  /// Where the layers of some nodes are.
  private struct Context {
    /// The transform from the coordinates of the nodes to the coordinates of the view.
    let transform: CGAffineTransform
    /// The transform from the coordinates of the nodes to the coordinates of the view without the transforms that
    /// animations change, which is the same at every time.
    let restingTransform: CGAffineTransform
    /// The rectangle of the view in its coordinates.
    let view: CGRect
    /// Whether no animation moves the nodes in the view, so that what's outside the view never shows.
    let isFixed: Bool
    /// Whether an animation changes the painting of a node around the nodes, which the nodes may inherit.
    let isChanging: Bool
    /// The key of the layer around the layers of the nodes.
    let key: LayerKey

    func inside(
      _ transform: CGAffineTransform, isFixed: Bool = true, isChanging: Bool = false, key: LayerKey.Component
    ) -> Context {
      Context(
        transform: transform.concatenating(self.transform),
        restingTransform: isFixed ? transform.concatenating(restingTransform) : restingTransform, view: view,
        isFixed: self.isFixed && isFixed,
        isChanging: self.isChanging || isChanging, key: self.key.appending(key))
    }
  }

  /// The layers of nodes in order: a painted layer for each run of nodes without layers of their own, and the
  /// layers of the other nodes between them.
  private func layers(of nodes: [RenderNode], in context: Context) -> [PlannedLayer] {
    var layers = [PlannedLayer]()
    var run = [RenderNode]()
    func paintRun() {
      if let layer = painted(run, in: context, changes: run.contains(where: changes)) {
        layers.append(.painted(layer))
      }
      run = []
    }
    for node in nodes {
      if let layer = container(of: node, in: context) {
        paintRun()
        layers.append(.container(layer))
      } else if isFilteredLayer(node) {
        paintRun()
        if let layer = painted([node], in: context, changes: true) {
          layers.append(.painted(layer))
        }
      } else {
        run.append(node)
      }
    }
    paintRun()
    return layers
  }

  /// The container layer of a node, or `nil` if the node is painted with the nodes around it, or into a painted layer
  /// of its own: when neither it nor a node in it gets a container of its own.
  private func container(of node: RenderNode, in context: Context) -> ContainerLayer? {
    let isPromoted = promoted.contains(node.id.element)
    guard isPromoted || containsOwnLayer(node) else { return nil }
    // An animation moves what the layer of a promoted node shows.
    let isFixed = !isPromoted
    let isChanging = painting?.contains(node.id.element) ?? true
    let key = LayerKey.Component.node(node.id)
    switch node {
    case .group(let group) where group.clip == nil && group.mask == nil:
      let inner = context.inside(group.transform, isFixed: isFixed, isChanging: isChanging, key: key)
      return ContainerLayer(
        id: group.id, transform: group.transform, opacity: group.opacity, clip: nil,
        children: layers(of: group.children, in: inner), key: inner.key)
    case .use(let use) where use.clip == nil && use.mask == nil:
      let transform = (use.instance?.translation ?? .identity).concatenating(use.transform)
      let inner = context.inside(transform, isFixed: isFixed, isChanging: isChanging, key: key)
      return ContainerLayer(
        id: use.id, transform: transform, opacity: use.instance?.opacity ?? 1, clip: nil,
        children: use.instance?.content.map { layers(of: [$0], in: inner) } ?? [], key: inner.key)
    case .viewport(let viewport) where viewport.content.map({ $0.clip == nil && $0.mask == nil }) ?? true:
      guard let content = viewport.content else { return nil }
      let transform = content.viewBoxTransform.concatenating(viewport.translation).concatenating(viewport.transform)
      let inner = context.inside(transform, isFixed: isFixed, isChanging: isChanging, key: key)
      // The overflow of a viewport is clipped in the coordinates of its content.
      let clipped =
        content.overflowClip.map { clip in
          let clipped = inner.inside(.identity, key: .index(0))
          return [
            PlannedLayer.container(
              ContainerLayer(
                id: nil, transform: .identity, opacity: 1, clip: clip,
                children: layers(of: content.children, in: clipped), key: clipped.key))
          ]
        } ?? layers(of: content.children, in: inner)
      return ContainerLayer(
        id: viewport.id, transform: transform, opacity: 1, clip: nil, children: clipped, key: inner.key)
    default:
      // A promoted node that paints as one image, or a shape, is painted in its own coordinates in its layer.
      let inner = context.inside(node.transform, isFixed: false, key: key)
      // The container composites the node, so only the painting of the node and of the nodes in it changes the
      // contents. The source of a filter is the element itself without its transform and its opacity, which the
      // container composites, so the nodes of the element don't change the contents by moving.
      let contentChanges =
        isChanging || node.descendants.contains { $0.id.element != node.id.element && changes($0) }
      return ContainerLayer(
        id: node.id, transform: node.transform, opacity: node.groupOpacity, clip: nil,
        children: painted([node.withoutCompositing], in: inner, changes: contentChanges).map { [.painted($0)] } ?? [],
        key: inner.key)
    }
  }

  /// Whether a node in the node gets a layer of its own, which it doesn't inside a node that composites what it
  /// paints as one image.
  private func containsOwnLayer(_ node: RenderNode) -> Bool {
    func isOrContainsOwnLayer(_ node: RenderNode) -> Bool {
      promoted.contains(node.id.element) || isFilteredLayer(node) || containsOwnLayer(node)
    }
    switch node {
    case .group(let group):
      return group.clip == nil && group.mask == nil && group.children.contains(where: isOrContainsOwnLayer)
    case .use(let use):
      guard use.clip == nil, use.mask == nil, let content = use.instance?.content else { return false }
      return isOrContainsOwnLayer(content)
    case .viewport(let viewport):
      guard let content = viewport.content, content.clip == nil, content.mask == nil else { return false }
      return content.children.contains(where: isOrContainsOwnLayer)
    case .shape, .filtered:
      return false
    }
  }

  /// Whether a node is a filtered node whose painting changes with the time, which is painted into a layer of its own.
  private func isFilteredLayer(_ node: RenderNode) -> Bool {
    guard case .filtered = node else { return false }
    return changes(node)
  }

  /// Whether what a node paints can change with the time: the painting or the compositing of it or of a node in it.
  private func changes(_ node: RenderNode) -> Bool {
    guard let painting else { return true }
    return ([node] + node.descendants).contains { painting.contains($0.id.element) || promoted.contains($0.id.element) }
  }

  /// The painted layer of nodes, or `nil` if they paint nothing that can show.
  ///
  /// - Parameter changes: Whether what the nodes paint can change with the time.
  private func painted(_ nodes: [RenderNode], in context: Context, changes: Bool) -> PaintedLayer? {
    guard !nodes.isEmpty else { return nil }
    let transform = context.transform
    // A rotation changes the scale by the error of the arithmetic, which mustn't make the contents of one time differ
    // from the next.
    func rounded(_ value: CGFloat) -> CGFloat {
      (scale * value * 1e6).rounded() / 1e6
    }
    let rasterScale = CGSize(
      width: rounded(hypot(transform.a, transform.b)), height: rounded(hypot(transform.c, transform.d)))
    guard rasterScale.width > 0, rasterScale.height > 0, rasterScale.width.isFinite, rasterScale.height.isFinite
    else { return nil }
    var bounds = nodes.paintedBounds
    if context.isFixed {
      // What's outside the view never shows, so the contents don't cover it.
      bounds = bounds.intersection(context.view.applying(transform.inverted()))
    }
    guard !bounds.isNull, !bounds.isEmpty else { return nil }
    bounds = bounds.insetBy(dx: -Self.margin / rasterScale.width, dy: -Self.margin / rasterScale.height)
    // The pixels of the contents lie on the pixels of the screen as the layer is without the transforms that
    // animations change, so that the layer shows the same pixels as a rendering into one bitmap there, and the
    // contents of one time can show at the next. Where an animation moves them between the pixels of the screen, the
    // screen resamples them. A rotation or a skew keeps them off the pixels of the screen, and a flip or a scale that
    // differs between the axes keeps them on.
    let resting = context.restingTransform
    if resting.b == 0, resting.c == 0 {
      let pixels = resting.concatenating(CGAffineTransform(scaleX: scale, y: scale))
      bounds = bounds.applying(pixels).integral.applying(pixels.inverted())
    } else if !context.isFixed {
      let pixels = CGAffineTransform(scaleX: rasterScale.width, y: rasterScale.height)
      bounds = bounds.applying(pixels).integral.applying(pixels.inverted())
    }
    return PaintedLayer(
      nodes: nodes, bounds: bounds, rasterScale: rasterScale, changes: changes || context.isChanging,
      key: context.key.appending(.nodes(nodes.map(\.id))))
  }
}

extension RenderNode {
  /// The nodes in the node, at every depth, including the source of a filtered node and the content of a `<use>`.
  var descendants: [RenderNode] {
    let children: [RenderNode] =
      switch self {
      case .shape: []
      case .group(let group): group.children
      case .viewport(let viewport): viewport.content?.children ?? []
      case .use(let use): use.instance?.content.map { [$0] } ?? []
      case .filtered(let filtered): filtered.source.map { [$0] } ?? []
      }
    return children.flatMap { [$0] + $0.descendants }
  }
}
