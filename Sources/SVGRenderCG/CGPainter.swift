import CoreGraphics
import Foundation
import SVGCore

/// Paints a render tree into a `CGContext`.
package struct CGPainter {
  /// The scale of the image being rendered.
  let scale: CGFloat

  package init(scale: CGFloat) {
    self.scale = scale
  }

  package func paint(_ tree: RenderTree, into graphics: CGContext) async {
    graphics.saveGState()
    for transform in tree.rootTransforms {
      graphics.concatenate(transform)
    }
    if let root = tree.root {
      await paint(root, into: graphics)
    }
    graphics.restoreGState()
  }

  /// Paints nodes in order, in the coordinates that the context has, as the parent of the nodes paints them where
  /// no clip or mask applies.
  ///
  /// A renderer that paints the nodes of a render tree into separate layers paints the nodes of each layer this way.
  package func paint(_ nodes: [RenderNode], into graphics: CGContext) async {
    for node in nodes {
      await paint(node, into: graphics)
    }
  }

  /// Paints a node.
  ///
  /// A clip or a mask that has been applied to the context since the last transparency layer applies to each
  /// drawing, so where one applies, `isClipped` is `true`, and a node that draws more than once paints in a layer of
  /// its own, so that the clip or the mask applies once to what it paints composited together.
  func paint(_ node: RenderNode, into graphics: CGContext, isClipped: Bool = false) async {
    guard !Task.isCancelled else { return }
    // Painting hardly ever suspends otherwise, so let other tasks run on this thread of the cooperative thread
    // pool between nodes.
    await Task.yield()
    switch node {
    case .shape(let shape):
      await paint(shape, into: graphics, isClipped: isClipped)
    case .group(let group):
      await paint(group, into: graphics, isClipped: isClipped)
    case .viewport(let viewport):
      await paint(viewport, into: graphics, isClipped: isClipped)
    case .use(let use):
      await paint(use, into: graphics, isClipped: isClipped)
    case .filtered(let filtered):
      await paint(filtered, into: graphics)
    }
  }

  private func paint(_ shape: ShapeNode, into graphics: CGContext, isClipped: Bool) async {
    graphics.saveGState()
    graphics.concatenate(shape.transform)
    var isClipped = isClipped
    if let clip = shape.clip {
      await apply(clip, to: graphics)
      isClipped = true
    }
    switch shape.mask {
    case .none:
      break
    case .clipToZero:
      graphics.clip(to: .zero)
      isClipped = true
    case .mask(let mask):
      await apply(mask, to: graphics)
      isClipped = true
    }
    if let path = shape.geometry?.path.cgPath, let content = shape.content {
      if isPaintedOnce(content) {
        // The opacity and the clips apply to the one drawing as they would to a layer.
        graphics.setAlpha(shape.opacity)
        await paint(content, path: path, into: graphics)
      } else {
        await inLayer(opacity: shape.opacity, isNeeded: isClipped, of: graphics) {
          await paint(content, path: path, into: graphics)
        }
      }
    }
    graphics.restoreGState()
  }

  /// Whether the content is painted by one drawing of a color, so that its opacity can apply to that drawing.
  private func isPaintedOnce(_ content: ShapeContent) -> Bool {
    switch content {
    case .vector(fill: .color?, stroke: nil, _), .vector(fill: nil, stroke: .some, _):
      true
    default:
      false
    }
  }

  /// Paints with `body` in a transparency layer, which composites what it paints together, only where the layer
  /// changes the result: when the opacity is less than 1, or when `isNeeded`, such as when a clip or a mask applies
  /// to what `body` paints composited together. Elsewhere `body` paints into the context directly, whose opacity is
  /// 1 there, since an element with a smaller opacity paints its content in a layer.
  private func inLayer(
    opacity: CGFloat, isNeeded: Bool, of graphics: CGContext, _ body: () async -> Void
  ) async {
    guard isNeeded || opacity != 1 else {
      await body()
      return
    }
    graphics.setAlpha(opacity)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    await body()
    graphics.endTransparencyLayer()
  }

  private func paint(_ content: ShapeContent, path: CGPath, into graphics: CGContext) async {
    switch content {
    case .vector(let fill, let stroke, let fillRule):
      if let fill {
        await paint(fill, path: path, fillRule: fillRule, into: graphics)
      }
      stroke.map { paint($0, path: path, into: graphics) }
    case .image(let image, let stroke):
      image.map { paintImage($0, in: path, graphics: graphics) }
      stroke.map { paint($0, path: path, into: graphics) }
    }
  }

  private func paint(_ fill: FillPaint, path: CGPath, fillRule: CGPathDrawingMode, into graphics: CGContext) async {
    switch fill {
    case .color(let color):
      graphics.setFillColor(color)
    case .gradient(let gradient):
      gradient?.paint(path, in: graphics)
      return
    case .pattern(let pattern):
      guard let pattern else { return }
      graphics.saveGState()
      await inLayer(opacity: pattern.opacity, isNeeded: false, of: graphics) {
        await paint(pattern, path: path, into: graphics)
      }
      graphics.restoreGState()
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

  private func paint(_ group: GroupNode, into graphics: CGContext, isClipped: Bool) async {
    graphics.saveGState()
    graphics.concatenate(group.transform)
    // The mask applies to the children composited together, so it clips the context that the layer is drawn into.
    if let mask = group.mask {
      await apply(mask, to: graphics)
    }
    let isClipped = isClipped || group.mask != nil
    let hasLayer = needsLayer(opacity: group.opacity, isClipped: isClipped, childCount: group.children.count)
    await inLayer(opacity: group.opacity, isNeeded: hasLayer, of: graphics) {
      // The clip path applies to each child.
      if let clip = group.clip {
        await apply(clip, to: graphics)
      }
      let isChildClipped = (isClipped && !hasLayer) || group.clip != nil
      for child in group.children {
        await paint(child, into: graphics, isClipped: isChildClipped)
      }
    }
    graphics.restoreGState()
  }

  private func paint(_ viewport: ViewportNode, into graphics: CGContext, isClipped: Bool) async {
    graphics.saveGState()
    graphics.concatenate(viewport.transform)
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
    if let mask = content.mask {
      await apply(mask, to: graphics)
    }
    let isClipped = isClipped || content.overflowClip != nil || content.mask != nil
    let hasLayer = needsLayer(opacity: 1, isClipped: isClipped, childCount: content.children.count)
    await inLayer(opacity: 1, isNeeded: hasLayer, of: graphics) {
      // The clip path applies to each child.
      if let clip = content.clip {
        await apply(clip, to: graphics)
      }
      let isChildClipped = (isClipped && !hasLayer) || content.clip != nil
      for child in content.children {
        await paint(child, into: graphics, isClipped: isChildClipped)
      }
    }
    graphics.restoreGState()
  }

  private func paint(_ use: UseNode, into graphics: CGContext, isClipped: Bool) async {
    graphics.saveGState()
    defer {
      graphics.restoreGState()
    }
    graphics.concatenate(use.transform)
    if let clip = use.clip {
      await apply(clip, to: graphics)
    }
    if let mask = use.mask {
      await apply(mask, to: graphics)
    }
    guard let instance = use.instance else { return }
    graphics.concatenate(instance.translation)
    guard let content = instance.content else { return }
    let isClipped = isClipped || use.clip != nil || use.mask != nil
    let hasLayer = needsLayer(opacity: instance.opacity, isClipped: isClipped, childCount: 1)
    await inLayer(opacity: instance.opacity, isNeeded: hasLayer, of: graphics) {
      await paint(content, into: graphics, isClipped: isClipped && !hasLayer)
    }
  }

  /// Whether a container paints its children in a layer: when it has an opacity, and when a clip or a mask applies
  /// to more than one child. One child paints in a layer of its own if it needs one.
  private func needsLayer(opacity: CGFloat, isClipped: Bool, childCount: Int) -> Bool {
    opacity != 1 || (isClipped && childCount > 1)
  }

  // MARK: - Clip paths

  /// Clips `target` to a clip path.
  private func apply(_ clip: ClipPathEffect, to target: CGContext) async {
    guard let image = await image(of: clip) else { return }
    target.clip(to: clip.frame, mask: image)
  }

  /// The bitmap of the bounds of the clipped element, whose alpha is the clip path, or `nil` if it can't be made.
  private func image(of clip: ClipPathEffect) async -> CGImage? {
    let size = clip.frame.size
    guard let graphics = CGContext.bitmap(size: size, scale: scale, space: CGColorSpaceCreateDeviceRGB()) else {
      return nil
    }
    // The clip path of the `<clipPath>` element is built for the same bounds, so its bitmap covers this one.
    if let clipPath = clip.clipPath {
      guard let image = await image(of: clipPath) else { return nil }
      graphics.clip(to: CGRect(x: 0, y: 0, width: graphics.width, height: graphics.height), mask: image)
    }
    // The units place the content in the user space of the clipped element, where the transform of the
    // `<clipPath>` element applies, and then the bounds move to the origin of the bitmap.
    let units: CGAffineTransform =
      switch clip.units {
      case .userSpaceOnUse: .identity
      case .objectBoundingBox:
        CGAffineTransform(a: size.width, b: 0, c: 0, d: size.height, tx: clip.frame.minX, ty: clip.frame.minY)
      }
    graphics.concatenate(
      units.concatenating(clip.transform)
        .concatenating(CGAffineTransform(translationX: -clip.frame.minX, y: -clip.frame.minY))
        .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
    for shape in clip.shapes {
      if Task.isCancelled { break }
      await Task.yield()
      graphics.saveGState()
      graphics.concatenate(shape.transform)
      if let clip = shape.clip {
        await apply(clip, to: graphics)
      }
      graphics.addPath(shape.path.cgPath)
      graphics.drawPath(using: shape.fillRule)
      graphics.restoreGState()
    }
    return graphics.makeImage()
  }

  // MARK: - Masks

  /// Clips `target` to a mask.
  private func apply(_ mask: MaskEffect, to target: CGContext) async {
    guard let image = await image(of: mask) else { return }
    target.clip(to: mask.region)
    target.clip(to: mask.frame, mask: image)
  }

  /// The bitmap of the bounds of the masked element, whose alpha is the luminance of the mask, or `nil` if it
  /// can't be made.
  private func image(of mask: MaskEffect) async -> CGImage? {
    let size = mask.frame.size
    guard let graphics = CGContext.bitmap(size: size, scale: scale, space: mask.colorInterpolation.colorSpace) else {
      return nil
    }
    let transform = CGAffineTransform(scaleX: scale, y: scale)
    switch mask.contentUnits {
    case .userSpaceOnUse:
      graphics.concatenate(transform.translatedBy(x: -mask.frame.minX, y: -mask.frame.minY))
    case .objectBoundingBox:
      graphics.concatenate(transform.scaledBy(x: size.width, y: size.height))
    }
    for content in mask.contents {
      if Task.isCancelled { break }
      await Task.yield()
      graphics.saveGState()
      graphics.concatenate(content.transform)
      if let clip = content.clip {
        await apply(clip, to: graphics)
      }
      if let mask = content.mask {
        await apply(mask, to: graphics)
      }
      await paint(content.fill, path: content.path.cgPath, into: graphics)
      graphics.restoreGState()
    }
    return graphics.makeImage().flatMap(luminanceToAlpha)
  }

  // MARK: - Patterns

  /// Fills a path with a pattern.
  private func paint(_ pattern: PatternPaint, path: CGPath, into graphics: CGContext) async {
    guard let tile = CGContext.bitmap(size: pattern.tileSize, scale: scale, space: pattern.colorInterpolation.colorSpace)
    else { return }
    tile.concatenate(pattern.transform.scaledBy(x: scale, y: scale).scale)
    pattern.viewBoxTransform.map { tile.concatenate($0) }
    for node in pattern.content {
      if Task.isCancelled { break }
      await Task.yield()
      tile.saveGState()
      await paint(node, into: tile)
      tile.restoreGState()
    }
    guard let tileImage = tile.makeImage() else { return }
    let drawPattern: CGPatternDrawPatternCallback = { info, context in
      guard let info = info else { return }
      let image = Unmanaged<CGImage>.fromOpaque(info).takeUnretainedValue()
      let size = CGSize(width: image.width, height: image.height)
      context.draw(image, in: CGRect(origin: .zero, size: size))
    }
    let releaseInfo: CGPatternReleaseInfoCallback = { info in
      guard let info = info else { return }
      Unmanaged<CGImage>.fromOpaque(info).release()
    }
    var callbacks = CGPatternCallbacks(version: 0, drawPattern: drawPattern, releaseInfo: releaseInfo)
    let scaleX = pattern.tileSize.width / CGFloat(tileImage.width)
    let scaleY = pattern.tileSize.height / CGFloat(tileImage.height)
    guard
      let cgPattern = CGPattern(
        info: Unmanaged.passRetained(tileImage).toOpaque(),
        bounds: CGRect(origin: .zero, size: pattern.frame.size),
        matrix: pattern.transform.withoutScaling
          .translatedBy(x: pattern.origin.x, y: pattern.origin.y)
          .scaledBy(x: scaleX, y: scaleY)
          .concatenating(graphics.ctm),
        xStep: CGFloat(tileImage.width),
        yStep: CGFloat(tileImage.height),
        tiling: .constantSpacing,
        isColored: true,
        callbacks: &callbacks
      ),
      let patternSpace = CGColorSpace(patternBaseSpace: nil)
    else { return }
    var alpha: CGFloat = 1
    graphics.addPath(path)
    graphics.setFillColorSpace(patternSpace)
    graphics.setFillPattern(cgPattern, colorComponents: &alpha)
    graphics.drawPath(using: .fill)
  }
}
