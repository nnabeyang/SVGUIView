import CoreGraphics
import Foundation
import SVGCore

/// Paints a render tree into a `CGContext`.
package struct CGPainter {
  /// The scale of the image being rendered.
  package let scale: CGFloat

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
    graphics.setShouldAntialias(shape.antialiases)
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
    if let geometry = shape.geometry, let content = shape.content {
      let path = geometry.path.cgPath
      if isPaintedOnce(content) {
        // The opacity, the blend mode and the clips apply to the one drawing as they would to a layer.
        graphics.setAlpha(shape.opacity)
        graphics.setBlendMode(shape.blendMode)
        await paint(content, path: path, frame: geometry.frame, into: graphics)
      } else {
        await inLayer(opacity: shape.opacity, blendMode: shape.blendMode, isNeeded: isClipped, of: graphics) {
          await paint(content, path: path, frame: geometry.frame, into: graphics)
        }
      }
    }
    graphics.restoreGState()
  }

  /// Whether the content is painted by one drawing of a color, so that its opacity can apply to that drawing.
  private func isPaintedOnce(_ content: ShapeContent) -> Bool {
    switch content {
    case .vector(fill: .color?, stroke: nil, _):
      true
    case .vector(fill: nil, stroke: .some(let stroke), _):
      if case .color = stroke.paint { true } else { false }
    default:
      false
    }
  }

  /// Paints with `body` in a transparency layer, which composites what it paints together, only where the layer
  /// changes the result: when the opacity is less than 1, when the layer blends with what's behind it, or when
  /// `isNeeded`, such as when a clip or a mask applies to what `body` paints composited together, or the layer is an
  /// isolation group. Elsewhere `body` paints into the context directly, whose opacity is 1 there, since an element
  /// with a smaller opacity paints its content in a layer.
  ///
  /// The layer is composited with the blend mode that the context has when it begins, and what `body` paints in it
  /// starts with the normal blend mode, so it blends only with what's in the layer.
  private func inLayer(
    opacity: CGFloat, blendMode: CGBlendMode = .normal, isNeeded: Bool, of graphics: CGContext,
    _ body: () async -> Void
  ) async {
    guard isNeeded || opacity != 1 || blendMode != .normal else {
      await body()
      return
    }
    graphics.setAlpha(opacity)
    graphics.setBlendMode(blendMode)
    graphics.beginTransparencyLayer(auxiliaryInfo: nil)
    await body()
    graphics.endTransparencyLayer()
  }

  /// Paints the content of a shape whose bounds without its stroke are `frame`, which the units of its paints use.
  private func paint(_ content: ShapeContent, path: CGPath, frame: CGRect, into graphics: CGContext) async {
    switch content {
    case .vector(let fill, let stroke, let fillRule):
      if let fill {
        await paint(fill, path: path, frame: path.boundingBoxOfPath, fillRule: fillRule, into: graphics)
      }
      if let stroke {
        await paint(stroke, path: path, frame: frame, into: graphics)
      }
    case .image(let image, let stroke):
      if let image {
        await paintImage(image, graphics: graphics)
      }
      if let stroke {
        await paint(stroke, path: path, frame: frame, into: graphics)
      }
    }
  }

  /// Paints the inside of a path, with the units of a gradient in `frame`.
  private func paint(
    _ fill: FillPaint, path: CGPath, frame: CGRect, fillRule: CGPathDrawingMode, into graphics: CGContext
  ) async {
    switch fill {
    case .color(let color):
      graphics.setFillColor(color)
    case .gradient(let gradient):
      gradient?.paint(path, frame: frame, in: graphics)
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

  /// Paints the stroke of a path. A stroke with a gradient or a pattern paints the outline of the stroke, with the
  /// units of its paint in the bounds of the shape without its stroke.
  private func paint(_ stroke: StrokeStyle, path: CGPath, frame: CGRect, into graphics: CGContext) async {
    let path = stroke.cap == .square ? Self.squareCapped(path) : path
    guard case .color(let color) = stroke.paint else {
      var outline = path
      if let dashes = stroke.dashes {
        outline = outline.copy(dashingWithPhase: stroke.dashOffset, lengths: dashes)
      }
      outline = outline.copy(
        strokingWithWidth: stroke.width, lineCap: stroke.cap, lineJoin: stroke.join, miterLimit: stroke.miterLimit)
      await paint(stroke.paint, path: outline, frame: frame, fillRule: .fill, into: graphics)
      return
    }
    graphics.setStrokeColor(color)
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

  /// The path with each subpath without length, which Core Graphics caps with a square turned by 45 degrees, made
  /// a short line along the x-axis, whose square caps are the square along the x-axis that SVG 2 specifies.
  private static func squareCapped(_ path: CGPath) -> CGPath {
    // The subpaths, with their start, whether they have a line or a curve, and whether a point of them isn't the
    // start. A subpath of a moveto alone has no caps.
    var subpaths = [(elements: [(CGPathElementType, [CGPoint])], start: CGPoint, hasSegment: Bool, hasLength: Bool)]()
    var hasEmptySubpath = false
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      let count =
        switch element.type {
        case .moveToPoint, .addLineToPoint: 1
        case .addQuadCurveToPoint: 2
        case .addCurveToPoint: 3
        case .closeSubpath: 0
        @unknown default: 0
        }
      let points = (0..<count).map { element.points[$0] }
      if element.type == .moveToPoint || subpaths.isEmpty {
        if let last = subpaths.last, last.hasSegment, !last.hasLength { hasEmptySubpath = true }
        subpaths.append(([], points.first ?? .zero, false, false))
      }
      subpaths[subpaths.count - 1].elements.append((element.type, points))
      if element.type != .moveToPoint, element.type != .closeSubpath {
        subpaths[subpaths.count - 1].hasSegment = true
      }
      if points.contains(where: { $0 != subpaths[subpaths.count - 1].start }) {
        subpaths[subpaths.count - 1].hasLength = true
      }
    }
    if let last = subpaths.last, last.hasSegment, !last.hasLength { hasEmptySubpath = true }
    guard hasEmptySubpath else { return path }
    let result = CGMutablePath()
    // A line too short to show, which only gives the caps their direction.
    let half: CGFloat = 1e-4
    for subpath in subpaths {
      guard subpath.hasLength || !subpath.hasSegment else {
        result.move(to: CGPoint(x: subpath.start.x - half, y: subpath.start.y))
        result.addLine(to: CGPoint(x: subpath.start.x + half, y: subpath.start.y))
        continue
      }
      for (type, points) in subpath.elements {
        switch type {
        case .moveToPoint: result.move(to: points[0])
        case .addLineToPoint: result.addLine(to: points[0])
        case .addQuadCurveToPoint: result.addQuadCurve(to: points[1], control: points[0])
        case .addCurveToPoint: result.addCurve(to: points[2], control1: points[0], control2: points[1])
        case .closeSubpath: result.closeSubpath()
        @unknown default: break
        }
      }
    }
    return result
  }

  private func paint(_ group: GroupNode, into graphics: CGContext, isClipped: Bool) async {
    graphics.saveGState()
    graphics.concatenate(group.transform)
    // The mask applies to the children composited together, so it clips the context that the layer is drawn into.
    if let mask = group.mask {
      await apply(mask, to: graphics)
    }
    let isClipped = isClipped || group.mask != nil
    let hasLayer =
      needsLayer(opacity: group.opacity, isClipped: isClipped, childCount: group.children.count)
      || group.isolates || group.blendMode != .normal
    await inLayer(opacity: group.opacity, blendMode: group.blendMode, isNeeded: hasLayer, of: graphics) {
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
    let hasLayer =
      needsLayer(opacity: viewport.opacity, isClipped: isClipped, childCount: content.children.count)
      || viewport.isolates || viewport.blendMode != .normal
    await inLayer(opacity: viewport.opacity, blendMode: viewport.blendMode, isNeeded: hasLayer, of: graphics) {
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
    let hasLayer =
      needsLayer(opacity: instance.opacity, isClipped: isClipped, childCount: 1) || use.isolates
      || use.blendMode != .normal
    await inLayer(opacity: instance.opacity, blendMode: use.blendMode, isNeeded: hasLayer, of: graphics) {
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
  ///
  /// - Parameter extent: The rectangle that the clip covers, which is the bounds of the clipped element by default,
  ///   and the filter region for the result of a filter, which can go past them.
  func apply(_ clip: ClipPathEffect, to target: CGContext, extent: CGRect? = nil) async {
    let (extent, scale) = bitmapExtent(of: extent ?? clip.frame, in: target)
    guard !extent.isNull else {
      target.clip(to: .zero)
      return
    }
    guard let image = await image(of: clip, extent: extent, scale: scale) else { return }
    target.clip(to: extent, mask: image)
  }

  /// The bitmap of `extent` at `scale`, whose alpha is the clip path, or `nil` if it can't be made.
  private func image(of clip: ClipPathEffect, extent: CGRect, scale: CGFloat) async -> CGImage? {
    let size = clip.frame.size
    guard let graphics = CGContext.bitmap(size: extent.size, scale: scale, space: CGColorSpaceCreateDeviceRGB())
    else {
      return nil
    }
    // The clip path of the `<clipPath>` element is built for the same bounds, and its bitmap covers the same extent.
    if let clipPath = clip.clipPath {
      guard let image = await image(of: clipPath, extent: extent, scale: scale) else { return nil }
      graphics.clip(to: CGRect(x: 0, y: 0, width: graphics.width, height: graphics.height), mask: image)
    }
    // The units place the content in the user space of the clipped element, where the transform of the
    // `<clipPath>` element applies, and then the extent moves to the origin of the bitmap.
    let units: CGAffineTransform =
      switch clip.units {
      case .userSpaceOnUse: .identity
      case .objectBoundingBox:
        CGAffineTransform(a: size.width, b: 0, c: 0, d: size.height, tx: clip.frame.minX, ty: clip.frame.minY)
      }
    graphics.concatenate(
      units.concatenating(clip.transform)
        .concatenating(CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
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
  ///
  /// - Parameter extent: The rectangle that the mask covers, which is the bounds of the masked element by default,
  ///   and the filter region for the result of a filter, which can go past them.
  func apply(_ mask: MaskEffect, to target: CGContext, extent: CGRect? = nil) async {
    let (extent, scale) = bitmapExtent(of: extent ?? mask.frame, in: target)
    guard !extent.isNull else {
      target.clip(to: .zero)
      return
    }
    guard let image = await image(of: mask, extent: extent, scale: scale) else { return }
    target.clip(to: mask.region)
    target.clip(to: extent, mask: image)
  }

  /// The rectangle and the scale of the bitmap of a clip path or a mask of `extent` that clips `target`, or a null
  /// rectangle if no part of `extent` can show.
  ///
  /// The bitmap is as fine as the pixels of `target`, where its user space is enlarged, such as by a viewBox or a
  /// transform, so that its edges are as sharp as they are without the enlargement, and never coarser than the scale
  /// of the painter. An enlarged bitmap covers only the part of `extent` that can show in `target`, on the grid of the
  /// pixels of the whole one, so that it has no more pixels than `target` shows.
  private func bitmapExtent(of extent: CGRect, in target: CGContext) -> (extent: CGRect, scale: CGFloat) {
    let ctm = target.ctm
    let targetScale = max(hypot(ctm.a, ctm.b), hypot(ctm.c, ctm.d))
    // A scale that differs from the painter's by rounding, such as of the fit of the document, keeps the bitmap of
    // the painter's scale.
    guard targetScale.isFinite, targetScale > scale * 1.001 else { return (extent, scale) }
    let visible = extent.intersection(target.boundingBoxOfClipPath)
    guard !visible.isNull, !visible.isEmpty else { return (.null, targetScale) }
    func edge(_ value: CGFloat, from origin: CGFloat, _ rule: FloatingPointRoundingRule) -> CGFloat {
      origin + ((value - origin) * targetScale).rounded(rule) / targetScale
    }
    let minX = edge(visible.minX, from: extent.minX, .down)
    let minY = edge(visible.minY, from: extent.minY, .down)
    let maxX = min(edge(visible.maxX, from: extent.minX, .up), extent.maxX)
    let maxY = min(edge(visible.maxY, from: extent.minY, .up), extent.maxY)
    return (CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), targetScale)
  }

  /// The bitmap of `extent` at `scale`, whose alpha is the luminance of the mask, or `nil` if it can't be made.
  private func image(of mask: MaskEffect, extent: CGRect, scale: CGFloat) async -> CGImage? {
    let size = mask.frame.size
    guard
      let graphics = CGContext.bitmap(size: extent.size, scale: scale, space: mask.colorInterpolation.colorSpace)
    else {
      return nil
    }
    let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -extent.minX, y: -extent.minY)
    switch mask.contentUnits {
    case .userSpaceOnUse:
      graphics.concatenate(transform)
    case .objectBoundingBox:
      graphics.concatenate(
        transform.translatedBy(x: mask.frame.minX, y: mask.frame.minY).scaledBy(x: size.width, y: size.height))
    }
    for node in mask.contents {
      if Task.isCancelled { break }
      await Task.yield()
      graphics.saveGState()
      await paint(node, into: graphics)
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
    // The transform from the space of the pattern, the pixels of the tile from the position of the pattern, to the
    // device.
    let matrix = pattern.transform.withoutScaling
      .translatedBy(x: pattern.origin.x, y: pattern.origin.y)
      .scaledBy(x: scaleX, y: scaleY)
      .concatenating(graphics.ctm)
    if paintCells(of: tileImage, matrix: matrix, path: path, into: graphics) { return }
    guard
      let cgPattern = CGPattern(
        info: Unmanaged.passRetained(tileImage).toOpaque(),
        bounds: CGRect(origin: .zero, size: pattern.frame.size),
        matrix: matrix,
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

  /// The most cells of a pattern that are drawn one by one.
  private static let maxCells = 10_000

  /// Fills a path with the cells of a pattern, each drawn into the rectangle that its corners round to on the pixels
  /// of the device, or returns `false` where the cells can't lie on the pixels: under a rotation or a skew, smaller
  /// than a pixel, or too many to draw one by one.
  ///
  /// The cells touch without gaps, and round to the same pixels in every bitmap whose pixels lie on the same grid,
  /// such as the contents of a layer, which start at another pixel. A pattern of Core Graphics rounds the cells from
  /// where the drawing starts, so the cells of the same pattern could lie a pixel apart in a layer and in one bitmap.
  ///
  /// - Parameter matrix: The transform from the space of the pattern, the pixels of the tile, to the device.
  private func paintCells(of tile: CGImage, matrix: CGAffineTransform, path: CGPath, into graphics: CGContext) -> Bool {
    let width = CGFloat(tile.width)
    let height = CGFloat(tile.height)
    guard matrix.b == 0, matrix.c == 0, abs(matrix.a) * width >= 1, abs(matrix.d) * height >= 1 else { return false }
    graphics.saveGState()
    defer { graphics.restoreGState() }
    graphics.addPath(path)
    graphics.clip()
    let visible = graphics.boundingBoxOfClipPath
    guard !visible.isEmpty else { return true }
    // The cells that cover what the clip shows, in the space of the pattern.
    let area = visible.applying(graphics.ctm).applying(matrix.inverted())
    let columns = Int((area.minX / width).rounded(.down))..<Int((area.maxX / width).rounded(.up))
    let rows = Int((area.minY / height).rounded(.down))..<Int((area.maxY / height).rounded(.up))
    guard columns.count * rows.count <= Self.maxCells else { return false }
    // A position halfway between pixels rounds up, even when the arithmetic of a bitmap that starts at another pixel
    // puts it a little below.
    func pixel(_ position: CGFloat) -> CGFloat {
      (position + 0.5 + 1e-6).rounded(.down)
    }
    // The cells round to at most two widths and two heights, so the tile is scaled to each size once, and the cells
    // are drawn without scaling.
    var cells = [CGSize: CGImage]()
    func cell(width cellWidth: CGFloat, height cellHeight: CGFloat) -> CGImage? {
      let key = CGSize(width: cellWidth, height: cellHeight)
      if let image = cells[key] { return image }
      guard
        let context = CGContext.bitmap(
          size: CGSize(width: abs(cellWidth), height: abs(cellHeight)), scale: 1,
          space: tile.colorSpace ?? CGColorSpaceCreateDeviceRGB())
      else { return nil }
      // The tile maps to the cell as the space of the pattern maps to the device, flipped where it flips.
      context.concatenate(
        CGAffineTransform(
          cellWidth / width, 0, 0, cellHeight / height, max(-cellWidth, 0), max(-cellHeight, 0)))
      context.draw(tile, in: CGRect(x: 0, y: 0, width: width, height: height))
      let image = context.makeImage()
      cells[key] = image
      return image
    }
    graphics.concatenate(graphics.ctm.inverted())
    for row in rows {
      for column in columns {
        let x = CGFloat(column) * width
        let y = CGFloat(row) * height
        let left = pixel(matrix.a * x + matrix.tx)
        let right = pixel(matrix.a * (x + width) + matrix.tx)
        let bottom = pixel(matrix.d * y + matrix.ty)
        let top = pixel(matrix.d * (y + height) + matrix.ty)
        guard left != right, bottom != top, let image = cell(width: right - left, height: top - bottom) else {
          continue
        }
        graphics.draw(
          image,
          in: CGRect(x: min(left, right), y: min(bottom, top), width: abs(right - left), height: abs(top - bottom)))
      }
    }
    return true
  }
}
