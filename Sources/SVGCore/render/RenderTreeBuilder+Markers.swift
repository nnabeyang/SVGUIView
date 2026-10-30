import CoreGraphics
import Foundation

extension RenderTreeBuilder {
  /// The markers of a shape at the vertices of its path, which are drawn after the shape, in the order of the
  /// vertices.
  ///
  /// A marker is a viewport at its vertex, whose content is the children of the `<marker>` element with the
  /// computed values that they have where the element is, not where the shape is. Each marker is a copy of the
  /// content of its own, which the shape and the place in the instance chain tell apart.
  func markerNodes(
    of element: any ShapeGeometry, context: ResolveContext, guard references: ReferenceGuard, instance: [ElementID]
  ) async -> [RenderNode] {
    let style = element.style
    let ids = (start: style.markerStart.id, mid: style.markerMid.id, end: style.markerEnd.id)
    guard ids.start != nil || ids.mid != nil || ids.end != nil, let data = element.markerPath(in: context) else {
      return []
    }
    let vertices = MarkerVertices.vertices(of: data)
    let strokeWidth = style.strokeWidth.value(context: context, mode: .other)
    var references = references
    if references.markers == nil {
      references = references.beginning(.markers)
    }
    var nodes = [RenderNode]()
    for (index, vertex) in vertices.enumerated() {
      let isStart = index == 0
      let isEnd = index == vertices.count - 1
      let placed: [(id: String?, isStart: Bool)] =
        if isStart || isEnd {
          [(isStart ? ids.start : nil, true), (isEnd ? ids.end : nil, false)]
        } else {
          [(ids.mid, false)]
        }
      for (id, isStart) in placed {
        guard !Task.isCancelled else { return nodes }
        guard let id, let marker = base.markers[id] else { continue }
        var markerReferences = references
        guard markerReferences.insert(marker: id) else { continue }
        // The instance chain tells the copies of the content apart with the shape and the number of the copy.
        let copy = ElementID(rawValue: -1 - nodes.count)
        if let node = await markerNode(
          marker, at: vertex, isStart: isStart, strokeWidth: strokeWidth, context: context,
          guard: markerReferences, instance: instance + [element.base.elementID, copy])
        {
          nodes.append(node)
        }
      }
    }
    return nodes
  }

  /// A marker at a vertex, or `nil` if it has no area.
  private func markerNode(
    _ marker: SVGMarkerElement, at vertex: MarkerVertex, isStart: Bool, strokeWidth: CGFloat,
    context: ResolveContext, guard references: ReferenceGuard, instance: [ElementID]
  ) async -> RenderNode? {
    let size = CGSize(
      width: marker.width?.value(context: context, mode: .width) ?? 3,
      height: marker.height?.value(context: context, mode: .height) ?? 3)
    let scale = marker.units == .strokeWidth ? strokeWidth : 1
    guard size.width > 0, size.height > 0, scale > 0 else { return nil }
    let viewBox = marker.viewBox?.toCGRect()
    if let viewBox, viewBox.width <= 0 || viewBox.height <= 0 { return nil }
    let viewBoxTransform =
      viewBox.map { (marker.preserveAspectRatio ?? PreserveAspectRatio()).getTransform(viewBox: $0, size: size) }
      ?? .identity
    let contentContext = ResolveContext(
      base: base, viewPort: viewPort, scale: self.scale,
      viewBox: viewBox ?? CGRect(origin: .zero, size: size)
    ).styled(by: marker)
    // The reference point is in the coordinates of the content, and is put at the vertex.
    let reference = CGPoint(
      x: marker.refX?.value(context: contentContext, mode: .width) ?? 0,
      y: marker.refY?.value(context: contentContext, mode: .height) ?? 0
    ).applying(viewBoxTransform)
    let transform = CGAffineTransform(translationX: vertex.point.x, y: vertex.point.y)
      .rotated(by: marker.angle(at: vertex, isStart: isStart) * .pi / 180)
      .scaledBy(x: scale, y: scale)
      .translatedBy(x: -reference.x, y: -reference.y)
    let overflowClip: CGRect? =
      switch marker.overflow ?? .hidden {
      case .visible, .auto: nil
      default: CGRect(origin: .zero, size: size).applying(viewBoxTransform.inverted())
      }
    var children = [RenderNode]()
    for child in marker.children {
      guard !Task.isCancelled else { break }
      guard let child = child as? (any SVGDrawableElement) else { continue }
      if let node = await node(of: child, context: contentContext, mode: .normal, guard: references, instance: instance) {
        children.append(node)
      }
    }
    return .viewport(
      ViewportNode(
        id: renderID(of: marker, instance: instance), transform: transform, translation: .identity, opacity: 1,
        content: ViewportContent(
          viewBoxTransform: viewBoxTransform, overflowClip: overflowClip, clip: nil, mask: nil, children: children)))
  }
}
