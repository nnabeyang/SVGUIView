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
        content.base.passesConditions,
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

  /// The mask of an element, or `nil` if it has none or its mask closes a cycle of masks.
  func mask(of element: some SVGElement) -> SVGMask? {
    guard case .url = element.style.mask, !cyclicMasks.contains(element.base.elementID) else { return nil }
    return element.style.mask
  }

  /// The elements in masks whose masks close cycles of masks.
  ///
  /// The masks are taken in the order of the document, and an element in a mask whose mask leads back to the mask,
  /// through the masks of the elements in the masks that it leads to, closes a cycle. The element is drawn without
  /// its mask wherever it's drawn, so that its cycle is removed as a whole, as resvg removes it. The masks of the
  /// elements in a later mask of the cycle still apply.
  static func findCyclicMasks(in base: SVGBaseContext) -> Set<ElementID> {
    var masks = [SVGMaskElement]()
    func collectMasks(in element: any SVGElement) {
      if let mask = element as? SVGMaskElement, let id = mask.id,
        base.masks[id]?.base.elementID == mask.base.elementID
      {
        masks.append(mask)
      }
      element.children.forEach(collectMasks)
    }
    if let root = base.root { collectMasks(in: root) }
    var cyclic = Set<ElementID>()
    // The elements in a mask with masks that are still drawn, and the IDs of their masks.
    func maskedElements(in element: any SVGElement) -> [(element: any SVGElement, id: String)] {
      element.children.flatMap { child -> [(element: any SVGElement, id: String)] in
        var elements = maskedElements(in: child)
        if case .url(let id) = child.style.mask, !cyclic.contains(child.base.elementID) {
          elements.insert((child, id), at: 0)
        }
        return elements
      }
    }
    // Whether the mask of an ID leads to the mask of another one.
    func leads(from id: String, to target: String) -> Bool {
      var visited = Set<String>()
      var pending = [id]
      while let id = pending.popLast() {
        guard id != target else { return true }
        guard visited.insert(id).inserted, let mask = base.masks[id] else { continue }
        pending += maskedElements(in: mask).map(\.id)
      }
      return false
    }
    for mask in masks {
      guard let id = mask.id else { continue }
      for (element, target) in maskedElements(in: mask) where leads(from: target, to: id) {
        cyclic.insert(element.base.elementID)
      }
    }
    return cyclic
  }

  /// The mask of an element, or `nil` if it masks nothing: for no mask, a cycle of masks, or bounds that have no
  /// pixel.
  ///
  /// - Parameters:
  ///   - frame: The bounds of the masked element.
  ///   - context: The context of the masked element, styled by it.
  ///   - instance: The identity of the content of the mask, for the masked element.
  func maskEffect(
    _ mask: SVGMask?, frame: CGRect, context: ResolveContext, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> MaskEffect? {
    var references = references
    guard case .url(let id) = mask,
      references.insert(mask: id),
      let element = base.masks[id],
      CGContext.bitmapLayout(size: frame.size, scale: scale) != nil
    else { return nil }
    let contentUnits = element.maskContentUnits ?? .userSpaceOnUse
    // The content is drawn in a context of its own, with the viewBox of the context, or the bounding box of the
    // masked element as 100% in its units. References in it continue the ones of the masked element, so that a
    // cycle of masks or patterns stops there.
    let contentContext = ResolveContext(
      base: base, viewPort: viewPort, scale: scale,
      viewBox: contentUnits == .objectBoundingBox ? CGRect(x: 0, y: 0, width: 1, height: 1) : context.viewBox)
    var contents = [RenderNode]()
    for child in element.children {
      guard !Task.isCancelled else { break }
      guard let child = child as? (any SVGDrawableElement),
        child.visibility != .hidden,
        child.display != CSSDisplay.none
      else { continue }
      if let node = await node(
        of: child, context: contentContext, mode: .normal, guard: references, instance: instance)
      {
        contents.append(node)
      }
    }
    let region = CGRect(
      x: (element.x ?? .percent(-10)).value(context: context, mode: .width),
      y: (element.y ?? .percent(-10)).value(context: context, mode: .height),
      width: (element.width ?? .percent(120)).value(context: context, mode: .width),
      height: (element.height ?? .percent(120)).value(context: context, mode: .height))
    return MaskEffect(
      frame: frame, region: region, contentUnits: contentUnits,
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
  /// The pattern with the attributes and the content of the patterns that it references, which it doesn't have,
  /// and the references with those patterns added.
  func mergedPattern(
    _ pattern: SVGPatternElement, guard references: ReferenceGuard
  ) -> (pattern: SVGPatternElement, references: ReferenceGuard) {
    var pattern = pattern
    var references = references
    while let parentId = pattern.parentId,
      let parent = base.patterns[parentId],
      references.insert(pattern: parentId)
    {
      pattern = SVGPatternElement(lhs: pattern, rhs: parent)
    }
    return (pattern, references)
  }

  func patternPaint(
    _ pattern: SVGPatternElement, frame: CGRect, opacity: CGFloat, context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> PatternPaint? {
    let (pattern, references) = mergedPattern(pattern, guard: references)
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
      // The coordinates of the content are fractions of the bounding box, which scales the content with its strokes
      // and its text, and 100% is the whole box.
      viewBoxTransform = CGAffineTransform(scaleX: frame.width, y: frame.height)
      viewBox = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    // The content is drawn in a context of its own, which shares the references of patterns. Other references have
    // a level only for an element drawn as the root.
    let tileContext = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: viewBox)
    var tileReferences = ReferenceGuard()
    tileReferences.patterns = references.patterns
    if mode == .root || mode == .filter(isRoot: true) {
      tileReferences = tileReferences.beginning([.uses, .clipPaths, .masks])
    }
    var content = [RenderNode]()
    for child in pattern.children {
      guard !Task.isCancelled else { break }
      guard let child = child as? (any SVGDrawableElement),
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
