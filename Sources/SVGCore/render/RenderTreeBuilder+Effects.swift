import CoreGraphics
import Foundation

extension RenderTreeBuilder {
  // MARK: - Clip paths

  /// The clip path of an element, or `nil` if it clips nothing: for no clip path, a cycle of clip paths, or bounds
  /// that have no pixel.
  ///
  /// - Parameters:
  ///   - frame: The bounds of the clipped element.
  ///   - context: The context of the clipped element, styled by it.
  func clipEffect(
    _ clipPath: SVGClipPath?, frame: CGRect, context: ResolveContext, guard references: ReferenceGuard
  ) async -> ClipPathEffect? {
    var references = references
    guard case .url(let id) = clipPath,
      references.insert(clipPath: id),
      let element = base.clipPaths[id],
      CGContext.bitmapLayout(size: frame.size, scale: scale) != nil
    else { return nil }
    var shapes = [ClipShape]()
    for child in element.children {
      guard !Task.isCancelled else { break }
      guard let content = child as? (any SVGDrawableElement),
        !(content is SVGGroupElement || content is SVGLineElement || content is SVGImageElement),
        content.visibility != .hidden,
        content.display != CSSDisplay.none,
        let path = await path(of: content, context: context.styled(by: content), guard: references)
      else { continue }
      shapes.append(
        ClipShape(
          path: RenderPath(path),
          transform: await transform(of: content, context: context.styled(by: content), frame: nil, guard: references),
          clip: await clipEffect(content.clipPath, frame: frame, context: context, guard: references),
          fillRule: await clipRule(of: content, context: context, guard: references) == .evenodd ? .eoFill : .fill))
    }
    // The box of a `<clipPath>` element is the one of its content, as the box of a group is.
    let transform = await transform(of: element.style, context: context.styled(by: element)) { box in
      await self.frame(
        of: element.children, context: context, includesStroke: box == .strokeBox, guard: references) ?? .zero
    }
    return ClipPathEffect(
      frame: frame, transform: transform, units: element.clipPathUnits ?? .userSpaceOnUse,
      shapes: shapes, clipPath: await clipEffect(element.clipPath, frame: frame, context: context, guard: references))
  }

  /// The clip rule of a child of a `<clipPath>` element. A `<use>` element takes the clip rule of the element that
  /// it references, whose copy it shows.
  private func clipRule(
    of element: any SVGDrawableElement, context: ResolveContext, guard references: ReferenceGuard
  ) async -> FillRule {
    guard let use = element as? SVGUseElement else { return element.style.clipRule }
    let rule = await withReferencedElement(of: use, context: context, guard: references) { element, references in
      await clipRule(of: element, context: context.styled(by: element), guard: references)
    }
    return rule ?? use.style.clipRule
  }

  // MARK: - Masks

  /// The mask of an element, or `nil` if it masks nothing: for no mask, a cycle of masks, or bounds that have no
  /// pixel.
  ///
  /// - Parameters:
  ///   - frame: The bounds of the masked element.
  ///   - context: The context of the masked element, styled by it.
  func maskEffect(
    _ mask: SVGMask?, frame: CGRect, context: ResolveContext, guard references: ReferenceGuard
  ) async -> MaskEffect? {
    var references = references
    guard case .url(let id) = mask,
      references.insert(mask: id),
      let element = base.masks[id],
      CGContext.bitmapLayout(size: frame.size, scale: scale) != nil
    else { return nil }
    // The content is filled in a context of its own, with the viewBox and nothing else of the context. References
    // in it continue the ones of the masked element, so that a cycle of patterns stops there.
    let fillContext = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: context.viewBox)
    var contents = [MaskContent]()
    for child in element.children {
      guard !Task.isCancelled else { break }
      guard let content = child as? (any SVGDrawableElement),
        !(content is SVGGroupElement || content is SVGLineElement),
        content.visibility != .hidden,
        content.display != CSSDisplay.none,
        let path = await path(of: content, context: context.styled(by: content), guard: references)
      else { continue }
      let fill: ShapeContent
      if let image = content as? SVGImageElement {
        fill = .image(image.decodedImage(), stroke: nil)
      } else {
        fill = .vector(
          fill: await fillPaint(
            of: content, path: path, context: fillContext, mode: .root, guard: references, instance: []),
          stroke: nil, fillRule: content.pathFillRule)
      }
      contents.append(
        MaskContent(
          path: RenderPath(path),
          transform: await transform(of: content, context: context.styled(by: content), frame: nil, guard: references),
          clip: await clipEffect(content.clipPath, frame: frame, context: context, guard: references),
          mask: await maskEffect(content.mask, frame: frame, context: context, guard: references), fill: fill))
    }
    let region = CGRect(
      x: (element.x ?? .percent(-10)).value(context: context, mode: .width),
      y: (element.y ?? .percent(-10)).value(context: context, mode: .height),
      width: (element.width ?? .percent(120)).value(context: context, mode: .width),
      height: (element.height ?? .percent(120)).value(context: context, mode: .height))
    return MaskEffect(
      frame: frame, region: region, contentUnits: element.maskContentUnits ?? .userSpaceOnUse,
      colorInterpolation: element.colorInterpolation ?? .sRGB, contents: contents)
  }

  // MARK: - Patterns

  /// The pattern that fills an element, or `nil` if its tile has no pixel.
  ///
  /// - Parameters:
  ///   - frame: The bounds of the filled element.
  ///   - context: The context of the filled element, styled by it.
  ///   - mode: How the filled element is drawn.
  ///   - references: The guard with the ID of the pattern added.
  ///   - instance: The identity of the content of the pattern, for the filled element.
  func patternPaint(
    _ pattern: SVGPatternElement, frame: CGRect, opacity: CGFloat, context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> PatternPaint? {
    var pattern = pattern
    var references = references
    while let parentId = pattern.parentId,
      let parent = base.patterns[parentId],
      references.insert(pattern: parentId)
    {
      pattern = SVGPatternElement(lhs: pattern, rhs: parent)
    }
    let transform = pattern.patternTransform?.matrix(box: context.viewBoxSize, context: context) ?? .identity
    let tileSize = pattern.size(frame: frame, context: context).applying(transform.scale)
    guard CGContext.bitmapLayout(size: tileSize, scale: scale) != nil else { return nil }

    let contentUnits = pattern.viewBox != nil ? .userSpaceOnUse : (pattern.patternContentUnits ?? .userSpaceOnUse)
    var viewBoxTransform: CGAffineTransform?
    let viewBox: CGRect
    switch contentUnits {
    case .userSpaceOnUse:
      if let patternViewBox = pattern.viewBox?.toCGRect() {
        viewBoxTransform = pattern.getTransform(viewBox: patternViewBox, size: tileSize)
        viewBox = patternViewBox
      } else {
        viewBox = context.viewBox
      }
    case .objectBoundingBox:
      viewBox = frame
    }
    // The content is drawn in a context of its own, which shares the references of patterns. Other references have
    // a level only for an element drawn as the root.
    let tileContext = ResolveContext(
      base: base, viewPort: viewPort, scale: scale, viewBox: viewBox, patternContentUnit: contentUnits)
    var tileReferences = ReferenceGuard()
    tileReferences.patterns = references.patterns
    if mode == .root || mode == .filter(isRoot: true) {
      tileReferences = tileReferences.beginning([.uses, .clipPaths, .masks])
    }
    var content = [RenderNode]()
    for child in pattern.children {
      guard !Task.isCancelled else { break }
      guard let child = child as? (any SVGDrawableElement),
        !(child is SVGGroupElement || child is SVGLineElement),
        child.visibility != .hidden,
        child.display != CSSDisplay.none
      else { continue }
      if let node = await node(
        of: child, context: tileContext, mode: .normal, guard: tileReferences, instance: instance)
      {
        content.append(node)
      }
    }

    let units = pattern.patternUnits ?? .objectBoundingBox
    let x = pattern.x?.value(context: context, mode: .width, unitType: units) ?? 0
    let y = pattern.y?.value(context: context, mode: .height, unitType: units) ?? 0
    let origin =
      switch units {
      case .userSpaceOnUse: CGPoint(x: x, y: y)
      case .objectBoundingBox: CGPoint(x: x * frame.width + frame.minX, y: y * frame.height + frame.minY)
      }
    return PatternPaint(
      opacity: opacity, tileSize: tileSize, transform: transform, origin: origin, frame: frame,
      viewBoxTransform: viewBoxTransform, colorInterpolation: pattern.colorInterpolation ?? .sRGB, content: content)
  }
}
