import CoreGraphics
import Foundation

/// Paints a render tree into a `CGContext`.
///
/// Clip paths, masks, patterns and filters are drawn by their elements for now, in an `SVGContext` made again from
/// the state that the render tree records for them.
struct CGPainter {
  let base: SVGBaseContext
  /// The rectangle that the document is rendered into.
  let viewPort: CGRect
  /// The scale of the image being rendered.
  let scale: CGFloat

  func paint(_ tree: RenderTree, into graphics: CGContext) async {
    graphics.saveGState()
    for transform in tree.rootTransforms {
      graphics.concatenate(transform)
    }
    if let root = tree.root {
      await paint(root, into: graphics)
    }
    graphics.restoreGState()
  }

  private func paint(_ node: RenderNode, into graphics: CGContext) async {
    guard !Task.isCancelled else { return }
    // Painting hardly ever suspends otherwise, so let other tasks run on this thread of the cooperative thread
    // pool between nodes.
    await Task.yield()
    switch node {
    case .shape(let shape):
      await paint(shape, into: graphics)
    case .group(let group):
      await paint(group, into: graphics)
    case .viewport(let viewport):
      await paint(viewport, into: graphics)
    case .use(let use):
      await paint(use, into: graphics)
    case .legacyFiltered(let filtered):
      let context = legacyContext(filtered.legacy, graphics: graphics)
      await filtered.filter.filter(content: filtered.element, context: context, cgContext: graphics)
    }
  }

  private func paint(_ shape: ShapeNode, into graphics: CGContext) async {
    // The clip path, the mask and the pattern of the element share the state of the drawing code of elements, as
    // they did when the element drew them.
    var legacy: SVGContext?
    func legacyContext() -> SVGContext {
      if let legacy { return legacy }
      let context = self.legacyContext(shape.legacy, graphics: graphics)
      legacy = context
      return context
    }
    graphics.saveGState()
    graphics.concatenate(shape.transform)
    if shape.geometry != nil {
      if let clip = shape.clip {
        await clip.clipPath.clipIfNeeded(frame: clip.frame, context: legacyContext(), cgContext: graphics)
      }
      switch shape.mask {
      case .none:
        break
      case .clipToZero:
        graphics.clip(to: .zero)
      case .mask(let mask, let frame):
        await mask.clipIfNeeded(frame: frame, context: legacyContext(), cgContext: graphics)
      }
    }
    graphics.setAlpha(shape.opacity)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let path = shape.geometry?.path.cgPath, let content = shape.content {
      switch content {
      case .vector(let fill, let stroke, let fillRule):
        if let fill {
          await paint(fill, path: path, fillRule: fillRule, into: graphics, legacy: legacyContext)
        }
        stroke.map { paint($0, path: path, into: graphics) }
      case .image(let image, let stroke):
        image.map { paintImage($0, in: path, graphics: graphics) }
        stroke.map { paint($0, path: path, into: graphics) }
      }
    }
    graphics.endTransparencyLayer()
    graphics.restoreGState()
  }

  private func paint(
    _ fill: FillPaint, path: CGPath, fillRule: CGPathDrawingMode, into graphics: CGContext,
    legacy: () -> SVGContext
  ) async {
    switch fill {
    case .color(let color):
      graphics.setFillColor(color)
    case .gradient(let gradient):
      gradient?.paint(path, in: graphics)
      return
    case .pattern(let pattern, let id, let frame, let opacity, let mode):
      let context = legacy()
      guard context.check(patternId: id) else {
        // A cycle of patterns stops the pattern, which paints black.
        graphics.setFillColor(CGColor.opaqueBlack)
        break
      }
      graphics.saveGState()
      graphics.setAlpha(opacity)
      graphics.beginTransparencyLayer(auxiliaryInfo: nil)
      _ = await pattern.pattern(path: path, frame: frame, context: context, cgContext: graphics, mode: mode)
      graphics.endTransparencyLayer()
      graphics.restoreGState()
      context.remove(patternId: id)
      return
    }
    graphics.addPath(path)
    graphics.drawPath(using: fillRule)
  }

  private func paint(_ stroke: StrokeStyle, path: CGPath, into graphics: CGContext) {
    if let color = stroke.color {
      graphics.setStrokeColor(color)
    }
    if let dashes = stroke.dashes {
      graphics.setLineDash(phase: stroke.dashOffset, lengths: dashes)
    }
    graphics.addPath(path)
    graphics.setLineWidth(stroke.width)
    graphics.setLineCap(stroke.cap)
    graphics.setLineJoin(stroke.join)
    graphics.setMiterLimit(stroke.miterLimit)
    graphics.drawPath(using: .stroke)
  }

  private func paint(_ group: GroupNode, into graphics: CGContext) async {
    graphics.saveGState()
    graphics.concatenate(group.transform)
    graphics.setAlpha(group.opacity)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let clip = group.clip {
      let context = legacyContext(group.legacy, graphics: graphics)
      await clip.clipPath.clipIfNeeded(frame: clip.frame, context: context, cgContext: graphics)
    }
    for child in group.children {
      await paint(child, into: graphics)
    }
    graphics.endTransparencyLayer()
    graphics.restoreGState()
  }

  private func paint(_ viewport: ViewportNode, into graphics: CGContext) async {
    graphics.saveGState()
    graphics.concatenate(viewport.translation)
    guard let content = viewport.content else {
      graphics.restoreGState()
      return
    }
    graphics.concatenate(content.viewBoxTransform)
    if let rect = content.overflowClip {
      let clip = CGMutablePath()
      clip.addRoundedRect(rect, cornerSize: .zero)
      graphics.addPath(clip)
      graphics.clip()
    }
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let clip = content.clip {
      let context = legacyContext(content.legacy, graphics: graphics)
      await clip.clipPath.clipIfNeeded(frame: clip.frame, context: context, cgContext: graphics)
    }
    for child in content.children {
      await paint(child, into: graphics)
    }
    graphics.endTransparencyLayer()
    graphics.restoreGState()
  }

  private func paint(_ use: UseNode, into graphics: CGContext) async {
    graphics.saveGState()
    defer {
      graphics.restoreGState()
    }
    graphics.concatenate(use.transform)
    if let clip = use.clip {
      let context = legacyContext(use.legacy, graphics: graphics)
      await clip.clipPath.clipIfNeeded(frame: clip.frame, context: context, cgContext: graphics)
    }
    guard let instance = use.instance else { return }
    graphics.concatenate(instance.translation)
    graphics.setAlpha(instance.opacity)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let content = instance.content {
      await paint(content, into: graphics)
    }
    graphics.endTransparencyLayer()
  }

  private func legacyContext(_ legacy: LegacyState, graphics: CGContext) -> SVGContext {
    SVGContext(base: base, graphics: graphics, viewPort: viewPort, scale: scale, legacy: legacy)
  }
}
