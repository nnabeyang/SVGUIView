import CoreGraphics
import Foundation

/// Where a shape is hit, as SVG 2 defines the targets of pointer events: its fill and its stroke, which
/// `pointer-events` and `visibility` choose from, in the coordinates of the shape.
package struct HitArea: Sendable {
  let pointerEvents: PointerEvents
  let isVisible: Bool
  /// Whether the fill isn't `none`, which an image always is.
  let fillsPainted: Bool
  /// Whether the stroke isn't `none`.
  let strokesPainted: Bool
  /// The area of the fill: the shape, or the cells of the glyphs of text.
  let fill: RenderPath
  let fillRule: CGPathDrawingMode
  /// The outline of the stroke with its dashes, caps and joins, or `nil` for a shape without a stroke width.
  let stroke: RenderPath?
  /// The object bounding box, which `bounding-box` hits.
  let bounds: CGRect
  /// Whether the fill is the cells of glyphs, where the fill and the stroke are both hit.
  let isCells: Bool
}

extension RenderTree {
  /// The elements whose shapes are at a point, from the front, each once.
  ///
  /// The tree is one built for hit testing, whose shapes have their areas. A shape is hit where its `pointer-events`
  /// targets it, and where its clip paths and the clip paths of its ancestors don't clip it out. Opacity, filters and
  /// masks don't change where it's hit, and neither does the content of its markers, as browsers hit-test them. A
  /// shape in the content of a `<use>` element is hit as the outermost `<use>` element.
  ///
  /// - Parameters:
  ///   - point: The point, in the coordinates that the tree is rendered in.
  ///   - tolerance: How far from a shape the point can be, in the same coordinates, which widens the areas.
  package func hits(at point: CGPoint, tolerance: CGFloat = 0) -> [ElementID] {
    guard let root else { return [] }
    var test = HitTest(point: point, tolerance: max(tolerance, 0))
    let transform = rootTransforms.reversed().reduce(CGAffineTransform.identity) { $0.concatenating($1) }
    test.visit(root, transform: transform)
    return test.elements
  }
}

/// A walk of a render tree from the front that collects the elements at a point.
private struct HitTest {
  let point: CGPoint
  let tolerance: CGFloat
  private(set) var elements = [ElementID]()
  private var found = Set<ElementID>()

  init(point: CGPoint, tolerance: CGFloat) {
    self.point = point
    self.tolerance = tolerance
  }

  /// Visits a node whose parent is drawn with a transform to the coordinates of the point.
  mutating func visit(_ node: RenderNode, transform parent: CGAffineTransform) {
    switch node {
    case .shape(let shape):
      let transform = shape.transform.concatenating(parent)
      guard let area = shape.hitArea, !Self.isMarker(shape.id), let local = local(transform) else { return }
      if let clip = shape.clip, !Self.contains(local, in: clip) { return }
      if case .clipToZero = shape.mask { return }
      if hits(area, transform: transform, local: local) {
        add(shape.id)
      }
    case .group(let group):
      let transform = group.transform.concatenating(parent)
      if let clip = group.clip {
        guard let local = local(transform), Self.contains(local, in: clip) else { return }
      }
      for child in group.children.reversed() {
        visit(child, transform: transform)
      }
    case .viewport(let viewport):
      guard let content = viewport.content else { return }
      let transform = content.viewBoxTransform.concatenating(viewport.translation)
        .concatenating(viewport.transform).concatenating(parent)
      if content.overflowClip != nil || content.clip != nil {
        guard let local = local(transform) else { return }
        if let rect = content.overflowClip, !rect.contains(local) { return }
        if let clip = content.clip, !Self.contains(local, in: clip) { return }
      }
      for child in content.children.reversed() {
        visit(child, transform: transform)
      }
    case .use(let use):
      let transform = use.transform.concatenating(parent)
      if let clip = use.clip {
        guard let local = local(transform), Self.contains(local, in: clip) else { return }
      }
      guard let instance = use.instance, let content = instance.content else { return }
      visit(content, transform: instance.translation.concatenating(transform))
    case .filtered(let filtered):
      // The filter doesn't change where the element is hit, and its clip path and mask apply in the coordinates of
      // the element.
      let transform = filtered.transform.concatenating(parent)
      if case .clipToZero = filtered.mask { return }
      if let clip = filtered.clip {
        guard let local = local(transform), Self.contains(local, in: clip) else { return }
      }
      if let source = filtered.source {
        visit(source, transform: transform)
      }
    }
  }

  /// The point in the coordinates that a transform draws, or `nil` if the transform can't be inverted.
  private func local(_ transform: CGAffineTransform) -> CGPoint? {
    guard transform.a * transform.d - transform.b * transform.c != 0 else { return nil }
    return point.applying(transform.inverted())
  }

  /// Whether a shape drawn with a transform is hit, whose coordinates have the point at `local`.
  private func hits(_ area: HitArea, transform: CGAffineTransform, local: CGPoint) -> Bool {
    let events = area.pointerEvents
    if events == .none || (events.needsVisibility && !area.isVisible) { return false }
    if events == .boundingBox {
      return hits(CGPath(rect: area.bounds, transform: nil), rule: .winding, transform: transform, local: local)
    }
    let fill = events.targetsFill(painted: area.fillsPainted)
    let stroke = events.targetsStroke(painted: area.strokesPainted)
    let rule: CGPathFillRule = area.fillRule == .eoFill ? .evenOdd : .winding
    if area.isCells {
      return (fill || stroke) && hits(area.fill.cgPath, rule: .winding, transform: transform, local: local)
    }
    if fill, hits(area.fill.cgPath, rule: rule, transform: transform, local: local) { return true }
    if stroke, let outline = area.stroke, hits(outline.cgPath, rule: .winding, transform: transform, local: local) {
      return true
    }
    return false
  }

  /// Whether a path drawn with a transform covers the point, or comes within the tolerance of it, which is measured
  /// in the coordinates of the point.
  private func hits(_ path: CGPath, rule: CGPathFillRule, transform: CGAffineTransform, local: CGPoint) -> Bool {
    let bounds = path.boundingBoxOfPath
    guard !bounds.isNull, bounds.applying(transform).insetBy(dx: -tolerance, dy: -tolerance).contains(point) else {
      return false
    }
    if path.contains(local, using: rule) { return true }
    guard tolerance > 0 else { return false }
    var transform = transform
    guard let drawn = path.copy(using: &transform) else { return false }
    return drawn.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
      .contains(point)
  }

  /// Adds the element of a shape: the outermost `<use>` element of the shapes in the content of `<use>` elements,
  /// and the element of the others.
  private mutating func add(_ id: RenderID) {
    let element = id.instance.first { $0.rawValue >= 0 } ?? id.element
    if found.insert(element).inserted {
      elements.append(element)
    }
  }

  /// Whether a shape is in the content of a marker, whose instance chain has the shape and the index of the marker.
  private static func isMarker(_ id: RenderID) -> Bool {
    id.instance.contains { $0.rawValue < 0 && $0.rawValue > Int.min / 4 }
  }

  /// Whether a clip path keeps a point in the coordinates of the element that it clips, as the painter draws it.
  private static func contains(_ point: CGPoint, in clip: ClipPathEffect) -> Bool {
    if let clipPath = clip.clipPath, !contains(point, in: clipPath) { return false }
    let units: CGAffineTransform =
      switch clip.units {
      case .userSpaceOnUse: .identity
      case .objectBoundingBox:
        CGAffineTransform(
          a: clip.frame.width, b: 0, c: 0, d: clip.frame.height, tx: clip.frame.minX, ty: clip.frame.minY)
      }
    let content = units.concatenating(clip.transform)
    guard content.a * content.d - content.b * content.c != 0 else { return false }
    let inContent = point.applying(content.inverted())
    for shape in clip.shapes {
      let transform = shape.transform
      guard transform.a * transform.d - transform.b * transform.c != 0 else { continue }
      let inShape = inContent.applying(transform.inverted())
      if let clip = shape.clip, !contains(inShape, in: clip) { continue }
      if shape.path.cgPath.contains(inShape, using: shape.fillRule == .eoFill ? .evenOdd : .winding) {
        return true
      }
    }
    return false
  }
}
