import CoreGraphics
import Foundation

/// Builds the render tree of a document for a rendering.
///
/// The builder follows the drawing code that the elements had step by step, so that the render tree paints what that
/// code drew: the same elements, with lengths resolved in the same contexts, and references followed or stopped at
/// the same places.
package struct RenderTreeBuilder {
  let base: SVGBaseContext
  /// The rectangle that the document is rendered into.
  let viewPort: CGRect
  /// The scale of the image being rendered.
  let scale: CGFloat
  /// The nodes of the render tree of another time that the tree can reuse.
  private let previous: RenderNodeCache
  /// The nodes that the tree makes or reuses that the tree of another time can reuse.
  private let reused = RenderNodeCollector()

  /// - Parameter previous: The nodes of the render tree of the document at another time, for the same rectangle,
  ///   scale and fit, which the nodes of elements that make the same nodes at every time reuse.
  package init(base: SVGBaseContext, viewPort: CGRect, scale: CGFloat, reusing previous: RenderNodeCache = .init()) {
    self.base = base
    self.viewPort = viewPort
    self.scale = scale
    self.previous = previous
  }

  /// The render tree, or `nil` if building it is cancelled.
  package func build(fit: ContentFit) async -> RenderTree? {
    guard let svg = base.root else { return RenderTree(rootTransforms: [], root: nil) }
    let viewBox = svg.getViewBox(size: viewPort.size)
    let context = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: viewBox)
    let height = (svg.height ?? .percent(100)).value(context: context, mode: .height)
    let width = (svg.width ?? .percent(100)).value(context: context, mode: .width)
    var transforms = [CGAffineTransform]()
    if fit.stretches {
      transforms.append(CGAffineTransform(scaleX: viewBox.width / width, y: viewBox.height / height))
    }
    transforms.append(fit.transform(viewBox: viewBox, size: viewPort.size))
    if fit.scales {
      let scale = viewBox.width / width
      transforms.append(CGAffineTransform(scaleX: scale, y: scale))
    }
    let root = await node(of: svg, context: context, mode: .root, guard: ReferenceGuard(), instance: [])
    guard !Task.isCancelled else { return nil }
    return RenderTree(rootTransforms: transforms, root: root, reusableNodes: reused.cache)
  }

  // MARK: - Nodes

  /// The node of an element, or `nil` if it draws nothing.
  ///
  /// An element whose node is the same at every time reuses its node of another time, which keeps the nodes in it.
  /// The content of a `<use>` element is styled by it, so it's the same only where the `<use>` elements that show it
  /// are the same too.
  func node(
    of element: any SVGDrawableElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode? {
    guard let scope = base.restyleScope, !scope.unstable.contains(element.base.elementID),
      !instance.contains(where: scope.unstable.contains)
    else {
      return await makeNode(of: element, context: context, mode: mode, guard: references, instance: instance)
    }
    let key = RenderNodeCache.Key(id: renderID(of: element, instance: instance), mode: mode)
    let node: RenderNode?
    if let previous = previous.nodes[key] {
      node = previous
    } else {
      node = await makeNode(of: element, context: context, mode: mode, guard: references, instance: instance)
    }
    if let node, !Task.isCancelled {
      reused.cache.nodes[key] = node
    }
    return node
  }

  private func makeNode(
    of element: any SVGDrawableElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode? {
    guard !Task.isCancelled else { return nil }
    // Building hardly ever suspends otherwise, so let other tasks run on this thread of the cooperative thread
    // pool between elements.
    await Task.yield()
    switch element {
    case let svg as SVGSVGElement:
      if svg.display == CSSDisplay.none { return nil }
      if case .filtered(let node) = await filtering(of: svg, context: context, guard: references, instance: instance) {
        return node
      }
      return await viewportNode(of: svg, context: context, mode: mode, guard: references, instance: instance)
    case let group as SVGGroupElement:
      if group.display == CSSDisplay.none { return nil }
      if case .filtered(let node) = await filtering(of: group, context: context, guard: references, instance: instance) {
        return node
      }
      return await groupNode(of: group, context: context, mode: mode, guard: references, instance: instance)
    case let use as SVGUseElement:
      if use.display == CSSDisplay.none { return nil }
      let references = beginsLevel(mode) ? references.beginning(.all) : references
      if case .filtered(let node) = await filtering(of: use, context: context, guard: references, instance: instance) {
        return node
      }
      return await useNode(of: use, context: context, mode: .normal, guard: references, instance: instance)
    case is SVGMaskElement, is SVGPatternElement:
      return nil
    default:
      if element.display == CSSDisplay.none { return nil }
      if case .filtered(let node) = await filtering(of: element, context: context, guard: references, instance: instance) {
        return node
      }
      return await shapeNode(of: element, context: context, mode: mode, guard: references, instance: instance)
    }
  }

  private func beginsLevel(_ mode: DrawMode) -> Bool {
    switch mode {
    case .root, .filter: true
    case .normal: false
    }
  }

  func renderID(of element: some SVGElement, instance: [ElementID]) -> RenderID {
    RenderID(element: element.base.elementID, instance: instance)
  }

  /// The node of an element without its filter.
  func nodeWithoutFilter(
    of element: any SVGDrawableElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode? {
    switch element {
    case let svg as SVGSVGElement:
      await viewportNode(of: svg, context: context, mode: mode, guard: references, instance: instance)
    case let group as SVGGroupElement:
      await groupNode(of: group, context: context, mode: mode, guard: references, instance: instance)
    case let use as SVGUseElement:
      await useNode(of: use, context: context, mode: mode, guard: references, instance: instance)
    default:
      await shapeNode(of: element, context: context, mode: mode, guard: references, instance: instance)
    }
  }

  private func shapeNode(
    of element: any SVGDrawableElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: element)
    let references = beginsLevel(mode) ? references.beginning(.all) : references
    if let text = element as? SVGTextElement, !text.children.isEmpty, let spans = text.spans(in: context),
      spans.contains(where: { $0.element !== text })
    {
      return await textNode(
        of: text, spans: spans, context: context, mode: mode, guard: references, instance: instance)
    }
    let path = await path(of: element, context: context, guard: references)
    var geometry: Geometry?
    var clip: ClipPathEffect?
    var mask = MaskApplication.none
    if let path {
      let frame = await frame(of: element, context: context, path: path, guard: references)
      geometry = Geometry(path: RenderPath(path), frame: frame)
      clip = await clipEffect(element.clipPath, frame: frame, context: context, guard: references)
      let lineWidth = element.style.strokeWidth.value(context: context, mode: .other)
      if case .url = element.style.mask, element.type == .line, frame.width == lineWidth || frame.height == lineWidth {
        mask = .clipToZero
      } else if let effect = await maskEffect(element.mask, frame: frame, context: context, guard: references) {
        mask = .mask(effect)
      }
    }
    let transform =
      mode != .filter(isRoot: true)
      ? await transform(of: element, context: context, frame: geometry?.frame ?? .zero, guard: references) : .identity
    var content: ShapeContent?
    if let path, element.style.visibility == .visible {
      let stroke = await stroke(
        of: element, path: path, context: context, mode: mode, guard: references, instance: instance)
      if let image = element as? SVGImageElement {
        content = .image(image.decodedImage(), stroke: stroke)
      } else {
        let fill = await fillPaint(
          of: element, path: path, context: context, mode: mode, guard: references, instance: instance)
        content = .vector(fill: fill, stroke: stroke, fillRule: element.pathFillRule)
      }
    }
    let id = renderID(of: element, instance: instance)
    let isClipped = if case .clipToZero = mask { true } else { false }
    let markers: [RenderNode] =
      if !isClipped, let shape = element as? any ShapeGeometry {
        await markerNodes(of: shape, context: context, guard: references, instance: instance)
      } else {
        []
      }
    guard !markers.isEmpty else {
      return .shape(
        ShapeNode(
          id: id, transform: transform, geometry: geometry, clip: clip, mask: mask, opacity: element.opacity,
          content: content))
    }
    // The markers are drawn after the shape, with its effects.
    let shape = ShapeNode(
      id: id, transform: .identity, geometry: geometry, clip: nil, mask: .none, opacity: 1, content: content)
    let groupMask: MaskEffect? = if case .mask(let effect) = mask { effect } else { nil }
    return .group(
      GroupNode(
        id: id, transform: transform, opacity: element.opacity, clip: clip, mask: groupMask,
        children: [.shape(shape)] + markers))
  }

  /// The node of text whose `<tspan>` descendants have glyphs: a group with the effects of the text, and a shape
  /// with the paints of each element for its glyphs.
  ///
  /// The shapes have the bounds of the whole text, so that a paint that they inherit from the text covers it as one.
  private func textNode(
    of text: SVGTextElement, spans: [TextSpan], context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> RenderNode {
    let frame = spans.reduce(CGRect.null) { $0.union($1.frame) }
    let clip = await clipEffect(text.clipPath, frame: frame, context: context, guard: references)
    let mask = await maskEffect(text.mask, frame: frame, context: context, guard: references)
    let transform =
      mode != .filter(isRoot: true)
      ? await transform(of: text, context: context, frame: frame, guard: references) : .identity
    var children = [RenderNode]()
    for span in spans {
      let element = span.element
      let context = context.styled(by: element)
      var content: ShapeContent?
      if element.style.visibility == .visible {
        let fill = await fillPaint(
          of: element, path: span.path, context: context, mode: mode, guard: references, instance: instance)
        content = .vector(
          fill: fill,
          stroke: await stroke(
            of: element, path: span.path, context: context, mode: mode, guard: references, instance: instance),
          fillRule: element.pathFillRule)
      }
      children.append(
        .shape(
          ShapeNode(
            id: renderID(of: element, instance: instance), transform: .identity,
            geometry: Geometry(path: RenderPath(span.path), frame: frame), clip: nil, mask: .none, opacity: 1,
            content: content)))
    }
    return .group(
      GroupNode(
        id: renderID(of: text, instance: instance), transform: transform, opacity: text.opacity, clip: clip,
        mask: mask, children: children))
  }

  private func groupNode(
    of group: SVGGroupElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: group)
    let references = beginsLevel(mode) ? references.beginning([.clipPaths, .masks]) : references
    var clip: ClipPathEffect?
    var mask: MaskEffect?
    var frame: CGRect?
    if group.clipPath != nil || group.mask != nil {
      let groupFrame = await self.frame(of: group, context: context, path: nil, guard: references)
      clip = await clipEffect(group.clipPath, frame: groupFrame, context: context, guard: references)
      mask = await maskEffect(group.mask, frame: groupFrame, context: context, guard: references)
      frame = groupFrame
    }
    let transform =
      mode != .filter(isRoot: true)
      ? await transform(of: group, context: context, frame: frame, guard: references) : .identity
    let childMode = mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode
    var children = [RenderNode]()
    for child in group.children {
      guard let child = child as? (any SVGDrawableElement) else { continue }
      if let node = await node(of: child, context: context, mode: childMode, guard: references, instance: instance) {
        children.append(node)
      }
    }
    return .group(
      GroupNode(
        id: renderID(of: group, instance: instance), transform: transform, opacity: group.opacity, clip: clip,
        mask: mask, children: children))
  }

  private func viewportNode(
    of svg: SVGSVGElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: svg)
    let id = renderID(of: svg, instance: instance)
    // The root element is placed by the view, and its transform isn't supported yet.
    let transform =
      mode != .filter(isRoot: true) && svg.base.elementID != base.root?.base.elementID
      ? await transform(of: svg, context: context, frame: nil, guard: references) : .identity
    let (translation, layout) = viewport(of: svg, context: context)
    guard let layout else {
      return .viewport(
        ViewportNode(id: id, transform: transform, translation: translation, opacity: svg.opacity, content: nil))
    }
    let inner = layout.context
    var overflowClip: CGRect?
    switch svg.overflow ?? .hidden {
    case .visible, .auto:
      break
    default:
      if svg.width != nil, svg.height != nil {
        overflowClip = layout.rect
      }
    }
    let references = beginsLevel(mode) ? references.beginning([.clipPaths, .masks]) : references
    let clip = await clipEffect(svg.clipPath, frame: inner.viewBox, context: inner, guard: references)
    let mask = await maskEffect(svg.mask, frame: inner.viewBox, context: inner, guard: references)
    let childMode = mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode
    var children = [RenderNode]()
    for child in svg.children {
      guard let child = child as? (any SVGDrawableElement) else { continue }
      if let node = await node(of: child, context: inner, mode: childMode, guard: references, instance: instance) {
        children.append(node)
      }
    }
    return .viewport(
      ViewportNode(
        id: id, transform: transform, translation: translation, opacity: svg.opacity,
        content: ViewportContent(
          viewBoxTransform: layout.viewBoxTransform, overflowClip: overflowClip, clip: clip, mask: mask,
          children: children)))
  }

  /// The content of a viewport, which has an area.
  private struct ViewportLayout {
    /// The transform from the coordinates of the content to the viewport.
    let viewBoxTransform: CGAffineTransform
    /// The viewport in the coordinates of its content.
    let rect: CGRect
    /// The context of the content.
    let context: ResolveContext
  }

  /// The translation of a viewport by `x` and `y`, and its content, or `nil` if it has no area, in a context styled by
  /// the `svg` element.
  private func viewport(
    of svg: SVGSVGElement, context: ResolveContext
  ) -> (translation: CGAffineTransform, layout: ViewportLayout?) {
    let x = (svg.x ?? .pixel(0)).value(context: context, mode: .width)
    let y = (svg.y ?? .pixel(0)).value(context: context, mode: .height)
    let translation = CGAffineTransform(translationX: x, y: y)
    let width = (svg.width ?? .percent(100)).value(context: context, mode: .width)
    let height = (svg.height ?? .percent(100)).value(context: context, mode: .height)
    guard height > 0, width > 0 else { return (translation, nil) }
    let viewPortSize = CGSize(width: width, height: height)
    let transform = svg.viewBox.map { svg.getTransform(viewBox: $0.toCGRect(), size: viewPortSize) } ?? .identity
    let rect = CGRect(origin: .zero, size: viewPortSize).applying(transform.inverted())
    return (
      translation,
      ViewportLayout(
        viewBoxTransform: transform, rect: rect, context: context.with(viewBox: svg.viewBox?.toCGRect() ?? rect))
    )
  }

  private func useNode(
    of use: SVGUseElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: use)
    let isFilterRoot = mode == .filter(isRoot: true)
    let references = isFilterRoot ? references.beginning(.all) : references
    var clip: ClipPathEffect?
    var mask: MaskEffect?
    var frame: CGRect?
    if use.clipPath != nil || use.mask != nil {
      let useFrame = await self.frame(of: use, context: context, path: nil, guard: references)
      clip = await clipEffect(use.clipPath, frame: useFrame, context: context, guard: references)
      mask = await maskEffect(use.mask, frame: useFrame, context: context, guard: references)
      frame = useFrame
    }
    let transform =
      isFilterRoot ? .identity : await transform(of: use, context: context, frame: frame, guard: references)
    let content = await withReferencedElement(of: use, context: context, guard: references) { element, references in
      UseInstance(
        translation: translation(of: use, context: context), opacity: use.opacity,
        content: await node(
          of: element, context: context, mode: .normal, guard: references,
          instance: instance + [use.base.elementID]))
    }
    return .use(
      UseNode(
        id: renderID(of: use, instance: instance), transform: transform, clip: clip, mask: mask, instance: content))
  }

  // MARK: - `<use>`

  /// Calls `body` with the element that the `<use>` element shows, with its computed values computed again with
  /// the `<use>` element as its parent, and the guard with the elements added, or returns `nil` if there is none or
  /// showing it would make a cycle.
  func withReferencedElement<T>(
    of use: SVGUseElement, context: ResolveContext, guard references: ReferenceGuard,
    _ body: (any SVGDrawableElement, ReferenceGuard) async -> T
  ) async -> T? {
    // A `<use>` element follows its reference also where no level of `<use>` elements has begun, such as in the
    // bounds of a group or in a clip path of a group, and the level stops a cycle from there.
    var references = references.uses == nil ? references.beginning(.uses) : references
    _ = references.insert(use: use.index)
    guard let parentId = use.parentId,
      let element = base[parentId],
      references.insert(use: element.index),
      !element.contains(index: use.index)
    else {
      return nil
    }
    let restyled = element.restyled(
      parent: use.style, root: base.root?.style ?? use.style, animations: base.isAnimated ? base.animations : nil)
    if let svg = restyled as? SVGSVGElement {
      return await body(svg.sized(width: use.width, height: use.height), references)
    }
    guard let restyled = restyled as? (any SVGDrawableElement) else { return nil }
    return await body(restyled, references)
  }

  private func translation(of use: SVGUseElement, context: ResolveContext) -> CGAffineTransform {
    let x = use.x?.value(context: context, mode: .width) ?? 0
    let y = use.y?.value(context: context, mode: .height) ?? 0
    return CGAffineTransform(translationX: x, y: y)
  }

  // MARK: - Geometry

  /// The shape of an element, in a context styled by the element.
  func path(
    of element: any SVGDrawableElement, context: ResolveContext, guard references: ReferenceGuard
  ) async -> CGPath? {
    switch element {
    case let shape as any ShapeGeometry:
      return shape.path(in: context)
    case let use as SVGUseElement:
      // An element with display none isn't rendered, also where a use element references it.
      let path = await withReferencedElement(of: use, context: context, guard: references) { element, references in
        element.display == CSSDisplay.none
          ? nil : await self.path(of: element, context: context.styled(by: element), guard: references)
      }
      var translation = translation(of: use, context: context)
      return path.flatMap { $0 }.flatMap { $0.copy(using: &translation) }
    default:
      // Groups, viewports and elements that aren't rendered, such as `<defs>`, `<mask>` and `<pattern>`, have no
      // shape.
      return nil
    }
  }

  /// The transform of an element about its transform origin, in a context styled by the element.
  ///
  /// - Parameter frame: The bounds of the element, if they're known.
  func transform(
    of element: any SVGDrawableElement, context: ResolveContext, frame: CGRect?, guard references: ReferenceGuard
  ) async -> CGAffineTransform {
    let transform = await transform(of: element.style, context: context) { box in
      if box == .fillBox, let frame { return frame }
      let path = await path(of: element, context: context, guard: references)
      return await self.frame(
        of: element, context: context, path: path, includesStroke: box == .strokeBox, guard: references)
    }
    // The motion of `<animateMotion>` applies after the transform, in the coordinates of the parent.
    return transform.concatenating(element.style.motion)
  }

  /// The transform of computed values about their transform origin.
  ///
  /// - Parameter reference: The reference box of the element for `fill-box` or `stroke-box`, which is found only for
  ///   a transform that isn't `none`.
  func transform(
    of style: ComputedStyle, context: ResolveContext, reference: (TransformBox) async -> CGRect
  ) async -> CGAffineTransform {
    let list = style.transform
    guard !list.functions.isEmpty else { return .identity }
    // The box of `view-box` starts at the origin of user space, also for a `viewBox` that doesn't.
    let box =
      style.transformBox == .viewBox ? CGRect(origin: .zero, size: context.viewBoxSize) : await reference(style.transformBox)
    let matrix = list.matrix(box: box.size, context: context)
    let origin = CGPoint(
      x: box.minX + style.transformOrigin.x.value(total: box.width, context: context),
      y: box.minY + style.transformOrigin.y.value(total: box.height, context: context))
    guard origin != .zero else { return matrix }
    return CGAffineTransform(translationX: -origin.x, y: -origin.y).concatenating(matrix)
      .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
  }

  /// The bounds that units relative to an element use, in a context styled by the element.
  ///
  /// - Parameter includesStroke: Whether the bounds are the stroke bounding box, which includes the strokes without
  ///   their dashes, instead of the object bounding box.
  func frame(
    of element: any SVGDrawableElement, context: ResolveContext, path: CGPath?, includesStroke: Bool = false,
    guard references: ReferenceGuard
  ) async -> CGRect {
    switch element {
    case let shape as any ShapeGeometry:
      let frame = shape.frame(in: context, path: path)
      // The bounds don't depend on what the stroke is painted with.
      guard includesStroke, !(shape is SVGTextElement), let path,
        let stroke = strokeStyle(of: shape, context: context, paint: .color(CGColor.opaqueBlack))
      else { return frame }
      let strokePath = path.copy(
        strokingWithWidth: stroke.width, lineCap: stroke.cap, lineJoin: stroke.join, miterLimit: stroke.miterLimit)
      return CGRectUnion(frame, strokePath.boundingBoxOfPath)
    case let group as SVGGroupElement:
      return await frame(of: group.children, context: context, includesStroke: includesStroke, guard: references)
        ?? .zero
    case let svg as SVGSVGElement:
      // The bounds of the children, each with its transform, in the coordinates that the viewport is placed in.
      let (translation, layout) = viewport(of: svg, context: context)
      guard let layout,
        let frame = await frame(
          of: svg.children, context: layout.context, includesStroke: includesStroke, guard: references)
      else { return .zero }
      return frame.applying(layout.viewBoxTransform.concatenating(translation))
    case let use as SVGUseElement:
      let frame = await withReferencedElement(of: use, context: context, guard: references) { element, references in
        let context = context.styled(by: element)
        return await self.frame(
          of: element, context: context, path: await self.path(of: element, context: context, guard: references),
          includesStroke: includesStroke, guard: references)
      }
      return (frame ?? .zero).applying(translation(of: use, context: context))
    default:
      return path?.boundingBoxOfPath ?? .zero
    }
  }

  /// The union of the bounds of elements, each with its transform, as the bounds of a group are, or `nil` if none of
  /// them is rendered.
  func frame(
    of children: [any SVGElement], context: ResolveContext, includesStroke: Bool = false,
    guard references: ReferenceGuard
  ) async -> CGRect? {
    var rect: CGRect?
    for child in children {
      guard let child = child as? (any SVGDrawableElement) else { continue }
      if case .none = child.display ?? .inline {
        continue
      }
      let context = context.styled(by: child)
      let childPath = await self.path(of: child, context: context, guard: references)
      let childFrame = await frame(
        of: child, context: context, path: childPath, includesStroke: includesStroke, guard: references)
      let transform = await transform(
        of: child, context: context, frame: includesStroke ? nil : childFrame, guard: references)
      let transformed = childFrame.applying(transform)
      rect = rect.map { CGRectUnion($0, transformed) } ?? transformed
    }
    return rect
  }

  // MARK: - Paint

  /// The paint of the fill of an element, or `nil` if it paints nothing.
  func fillPaint(
    of element: any SVGDrawableElement, path: CGPath, context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> FillPaint? {
    await paint(
      element.style.fill, opacity: element.style.fillOpacity, of: element, path: path, context: context, mode: mode,
      guard: references, instance: instance)
  }

  /// What a value of `fill` or `stroke` paints with, or `nil` if it paints nothing. The units of a paint server
  /// are the bounds of the element without its stroke, for its fill and its stroke alike.
  private func paint(
    _ value: Paint, opacity: CGFloat, of element: any SVGDrawableElement, path: CGPath, context: ResolveContext,
    mode: DrawMode, guard references: ReferenceGuard, instance: [ElementID]
  ) async -> FillPaint? {
    let style = element.style
    switch style.resolved(value) {
    case .none:
      return nil
    case .color(let color):
      // A color that isn't known, such as a misspelled name, paints nothing.
      return color.toCGColor(opacity: opacity).map { .color($0) }
    case .url(let id, let fallback):
      // An element without width or height has no bounding box for a paint server with objectBoundingBox units,
      // which paints the fallback instead.
      let bounds = path.boundingBoxOfPath
      let isEmpty = bounds.width == 0 || bounds.height == 0
      let fallbackPaint: FillPaint? =
        if case .color(let color)? = fallback { color.toCGColor(opacity: opacity).map { .color($0) } } else { nil }
      if let server = base.pservers[id] {
        // Display doesn't apply to paint servers, which are never rendered themselves.
        let gradient = gradientPaint(of: server, context: context, opacity: opacity)
        if isEmpty, gradient?.units == .objectBoundingBox { return fallbackPaint }
        return .gradient(gradient)
      } else if let pattern = base.patterns[id] {
        // A cycle of patterns stops the pattern, which paints black.
        var references = references
        if references.insert(pattern: id) {
          let merged = mergedPattern(pattern, guard: references).pattern
          if isEmpty,
            merged.patternUnits ?? .objectBoundingBox == .objectBoundingBox
              || merged.patternContentUnits == .objectBoundingBox
          {
            return fallbackPaint
          }
          let frame = await frame(of: element, context: context, path: path, guard: references)
          // A pattern without width or height, such as one that references nothing for them, paints the fallback.
          let size = merged.size(frame: frame, context: context)
          guard size.width > 0, size.height > 0 else { return fallbackPaint }
          return .pattern(
            await patternPaint(
              pattern, frame: frame, opacity: opacity, context: context, mode: mode, guard: references,
              instance: instance + [element.base.elementID]))
        }
        return .color(CGColor.opaqueBlack)
      }
      // A reference to an element that doesn't exist or isn't a paint server paints the fallback, or nothing.
      return fallbackPaint
    case .currentColor:
      preconditionFailure("currentColor is resolved")
    }
  }

  /// The gradient with the attributes of the gradients that it references, which it doesn't have.
  private func gradientPaint(
    of server: any SVGGradientServer, context: ResolveContext, opacity: CGFloat
  ) -> GradientPaint? {
    if let id = server.parentId,
      let parent = base.pservers[id],
      let merged = server.merged(other: parent)
    {
      return gradientPaint(of: merged, context: context, opacity: opacity)
    }
    return server.paint(context: context, opacity: opacity)
  }

  /// The stroke of an element, or `nil` if it paints none.
  private func stroke(
    of element: any SVGDrawableElement, path: CGPath, context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> StrokeStyle? {
    let style = element.style
    guard
      let paint = await paint(
        style.stroke, opacity: style.strokeOpacity, of: element, path: path, context: context, mode: mode,
        guard: references, instance: instance)
    else { return nil }
    return strokeStyle(of: element, context: context, paint: paint)
  }

  /// The stroke of an element with what it's painted with, or `nil` if the element has no stroke.
  private func strokeStyle(
    of element: any SVGDrawableElement, context: ResolveContext, paint: FillPaint
  ) -> StrokeStyle? {
    let style = element.style
    if case .none = style.stroke { return nil }
    let dashes = style.strokeDasharray.map { $0.value(context: context, mode: .other) }
    return StrokeStyle(
      paint: paint,
      dashes: dashes.contains { $0 > 0 } ? dashes : nil,
      dashOffset: style.strokeDashoffset.value(context: context, mode: .other),
      width: style.strokeWidth.value(context: context, mode: .other),
      cap: style.strokeLinecap,
      join: style.strokeLinejoin,
      miterLimit: style.strokeMiterlimit)
  }
}
