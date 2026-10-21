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

  func paint(_ node: RenderNode, into graphics: CGContext) async {
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
    case .filtered(let filtered):
      await paint(filtered, into: graphics)
    }
  }

  private func paint(_ shape: ShapeNode, into graphics: CGContext) async {
    graphics.saveGState()
    graphics.concatenate(shape.transform)
    if let clip = shape.clip {
      await apply(clip, to: graphics, level: graphics)
    }
    switch shape.mask {
    case .none:
      break
    case .clipToZero:
      graphics.clip(to: .zero)
    case .mask(let mask):
      await apply(mask, to: graphics, level: graphics)
    }
    graphics.setAlpha(shape.opacity)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let path = shape.geometry?.path.cgPath, let content = shape.content {
      await paint(content, path: path, into: graphics)
    }
    graphics.endTransparencyLayer()
    graphics.restoreGState()
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
      graphics.saveGState()
      graphics.setAlpha(pattern?.opacity ?? 1)
      graphics.beginTransparencyLayer(auxiliaryInfo: nil)
      if let pattern {
        await paint(pattern, path: path, into: graphics)
      }
      graphics.endTransparencyLayer()
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

  private func paint(_ group: GroupNode, into graphics: CGContext) async {
    graphics.saveGState()
    graphics.concatenate(group.transform)
    // The mask applies to the children composited together, so it clips the context that the layer is drawn into.
    if let mask = group.mask {
      await apply(mask, to: graphics, level: graphics)
    }
    graphics.setAlpha(group.opacity)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let clip = group.clip {
      await apply(clip, to: graphics, level: graphics)
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
    if let mask = content.mask {
      await apply(mask, to: graphics, level: graphics)
    }
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    if let clip = content.clip {
      await apply(clip, to: graphics, level: graphics)
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
      await apply(clip, to: graphics, level: graphics)
    }
    if let mask = use.mask {
      await apply(mask, to: graphics, level: graphics)
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

  // MARK: - Clip paths

  /// Clips `target` to a clip path.
  ///
  /// - Parameter level: The context that the clipped element is drawn into, which the clip path of the `<clipPath>`
  ///   element clips (svg_ui_view-90).
  private func apply(_ clip: ClipPathEffect, to target: CGContext, level: CGContext) async {
    guard let image = await image(of: clip, level: level) else { return }
    target.clip(to: clip.frame, mask: image)
  }

  /// The bitmap of the bounds of the clipped element, whose alpha is the clip path, or `nil` if it can't be made.
  private func image(of clip: ClipPathEffect, level: CGContext) async -> CGImage? {
    let size = clip.frame.size
    guard let graphics = CGContext.bitmap(size: size, scale: scale, space: CGColorSpaceCreateDeviceRGB()) else {
      return nil
    }
    let transform = clip.transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    switch clip.units {
    case .userSpaceOnUse:
      graphics.concatenate(transform.translatedBy(x: -clip.frame.minX, y: -clip.frame.minY))
    case .objectBoundingBox:
      graphics.concatenate(transform.scaledBy(x: size.width, y: size.height))
    }
    for shape in clip.shapes {
      if Task.isCancelled { break }
      await Task.yield()
      graphics.saveGState()
      graphics.concatenate(shape.transform)
      if let clip = shape.clip {
        await apply(clip, to: graphics, level: level)
      }
      graphics.addPath(shape.path.cgPath)
      graphics.drawPath(using: shape.fillRule)
      graphics.restoreGState()
    }
    if let clipPath = clip.clipPath {
      await apply(clipPath, to: level, level: level)
    }
    return graphics.makeImage()
  }

  // MARK: - Masks

  /// Clips `target` to a mask.
  ///
  /// - Parameter level: The context that the masked element is drawn into, which the clip paths of `<clipPath>`
  ///   elements in the mask clip (svg_ui_view-90).
  private func apply(_ mask: MaskEffect, to target: CGContext, level: CGContext) async {
    guard let image = await image(of: mask, level: level) else { return }
    target.clip(to: mask.region)
    target.clip(to: mask.frame, mask: image)
  }

  /// The bitmap of the bounds of the masked element, whose alpha is the luminance of the mask, or `nil` if it
  /// can't be made.
  private func image(of mask: MaskEffect, level: CGContext) async -> CGImage? {
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
        await apply(clip, to: graphics, level: level)
      }
      if let mask = content.mask {
        await apply(mask, to: graphics, level: level)
      }
      await paint(content.fill, path: content.path.cgPath, into: graphics)
      graphics.restoreGState()
    }
    if let clip = mask.clipPath {
      await apply(clip, to: graphics, level: level)
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
    if let clip = pattern.clipPath {
      await apply(clip, to: tile, level: graphics)
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
