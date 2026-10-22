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

  package init(base: SVGBaseContext, viewPort: CGRect, scale: CGFloat) {
    self.base = base
    self.viewPort = viewPort
    self.scale = scale
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
    return RenderTree(rootTransforms: transforms, root: root)
  }

  // MARK: - Nodes

  /// The node of an element, or `nil` if it draws nothing.
  func node(
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

  private func renderID(of element: some SVGElement, instance: [ElementID]) -> RenderID {
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
    let transform = mode != .filter(isRoot: true) ? (element.transform ?? .identity) : .identity
    let references = beginsLevel(mode) ? references.beginning(.all) : references
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
    var content: ShapeContent?
    if let path, element.style.visibility == .visible {
      let stroke = strokeStyle(of: element, context: context)
      if let image = element as? SVGImageElement {
        content = .image(image.decodedImage(), stroke: stroke)
      } else {
        let fill = await fillPaint(
          of: element, path: path, context: context, mode: mode, guard: references, instance: instance)
        content = .vector(fill: fill, stroke: stroke, fillRule: element.pathFillRule)
      }
    }
    return .shape(
      ShapeNode(
        id: renderID(of: element, instance: instance), transform: transform, geometry: geometry, clip: clip,
        mask: mask, opacity: element.opacity, content: content))
  }

  private func groupNode(
    of group: SVGGroupElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: group)
    let transform = mode != .filter(isRoot: true) ? (group.transform ?? .identity) : .identity
    let references = beginsLevel(mode) ? references.beginning([.clipPaths, .masks]) : references
    var clip: ClipPathEffect?
    var mask: MaskEffect?
    if group.clipPath != nil || group.mask != nil {
      let frame = await frame(of: group, context: context, path: nil, guard: references)
      clip = await clipEffect(group.clipPath, frame: frame, context: context, guard: references)
      mask = await maskEffect(group.mask, frame: frame, context: context, guard: references)
    }
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
    let x = (svg.x ?? .pixel(0)).value(context: context, mode: .width)
    let y = (svg.y ?? .pixel(0)).value(context: context, mode: .height)
    let translation = CGAffineTransform(translationX: x, y: y)
    let width = (svg.width ?? .percent(100)).value(context: context, mode: .width)
    let height = (svg.height ?? .percent(100)).value(context: context, mode: .height)
    guard height > 0, width > 0 else {
      return .viewport(ViewportNode(id: id, translation: translation, content: nil))
    }
    let viewPortSize = CGSize(width: width, height: height)
    let transform = svg.viewBox.map { svg.getTransform(viewBox: $0.toCGRect(), size: viewPortSize) } ?? .identity
    let rect = CGRect(origin: .zero, size: viewPortSize).applying(transform.inverted())
    let inner = context.with(viewBox: svg.viewBox?.toCGRect() ?? rect)
    var overflowClip: CGRect?
    switch svg.overflow ?? .hidden {
    case .visible, .auto:
      break
    default:
      if svg.width != nil, svg.height != nil {
        overflowClip = rect
      }
    }
    let references = beginsLevel(mode) ? references.beginning([.clipPaths, .masks]) : references
    let clip = await clipEffect(svg.clipPath, frame: inner.viewBox, context: inner, guard: references)
    let mask = await maskEffect(svg.mask, frame: inner.viewBox, context: inner, guard: references)
    var children = [RenderNode]()
    for child in svg.children {
      guard let child = child as? (any SVGDrawableElement) else { continue }
      if let node = await node(of: child, context: inner, mode: mode, guard: references, instance: instance) {
        children.append(node)
      }
    }
    return .viewport(
      ViewportNode(
        id: id, translation: translation,
        content: ViewportContent(
          viewBoxTransform: transform, overflowClip: overflowClip, clip: clip, mask: mask, children: children)))
  }

  private func useNode(
    of use: SVGUseElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: use)
    let isFilterRoot = mode == .filter(isRoot: true)
    let transform = isFilterRoot ? .identity : (use.transform ?? .identity)
    let references = isFilterRoot ? references.beginning(.all) : references
    var clip: ClipPathEffect?
    var mask: MaskEffect?
    if use.clipPath != nil || use.mask != nil {
      let frame = await frame(of: use, context: context, path: nil, guard: references)
      clip = await clipEffect(use.clipPath, frame: frame, context: context, guard: references)
      mask = await maskEffect(use.mask, frame: frame, context: context, guard: references)
    }
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
    let restyled = element.restyled(parent: use.style, root: base.root?.style ?? use.style)
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
      let path = await withReferencedElement(of: use, context: context, guard: references) { element, references in
        await self.path(of: element, context: context.styled(by: element), guard: references)
      }
      var translation = translation(of: use, context: context)
      return path.flatMap { $0 }.flatMap { $0.copy(using: &translation) }
    default:
      // Groups, viewports and elements that aren't rendered, such as `<defs>`, `<mask>` and `<pattern>`, have no
      // shape.
      return nil
    }
  }

  /// The bounds that units relative to an element use, in a context styled by the element.
  func frame(
    of element: any SVGDrawableElement, context: ResolveContext, path: CGPath?, guard references: ReferenceGuard
  ) async -> CGRect {
    switch element {
    case let shape as any ShapeGeometry:
      return shape.frame(in: context, path: path)
    case let group as SVGGroupElement:
      var rect: CGRect?
      for child in group.children {
        guard let child = child as? (any SVGDrawableElement) else { continue }
        if case .none = child.display ?? .inline {
          continue
        }
        let context = context.styled(by: child)
        let childPath = await self.path(of: child, context: context, guard: references)
        let childFrame = await frame(of: child, context: context, path: childPath, guard: references)
          .applying(child.transform ?? .identity)
        rect = rect.map { CGRectUnion($0, childFrame) } ?? childFrame
      }
      return rect ?? .zero
    case let svg as SVGSVGElement:
      var rect = CGRect.zero
      for child in svg.children {
        guard let child = child as? (any SVGDrawableElement), child.display != CSSDisplay.none else { continue }
        let context = context.styled(by: child)
        let childPath = await self.path(of: child, context: context, guard: references)
        rect = CGRectUnion(rect, await frame(of: child, context: context, path: childPath, guard: references))
      }
      return rect
    case let use as SVGUseElement:
      let frame = await withReferencedElement(of: use, context: context, guard: references) { element, references in
        let context = context.styled(by: element)
        return await self.frame(
          of: element, context: context, path: await self.path(of: element, context: context, guard: references),
          guard: references)
      }
      return (frame ?? .zero).applying(translation(of: use, context: context))
    default:
      return path?.boundingBoxOfPath ?? .zero
    }
  }

  // MARK: - Paint

  /// The paint of the fill of an element, or `nil` if it paints nothing.
  func fillPaint(
    of element: any SVGDrawableElement, path: CGPath, context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> FillPaint? {
    let style = element.style
    let opacity = style.fillOpacity
    switch style.resolved(style.fill) {
    case .none:
      return nil
    case .color(let color):
      // A color that isn't known, such as a misspelled name, paints nothing.
      return color.toCGColor(opacity: opacity).map { .color($0) }
    case .url(let id):
      if let server = base.pservers[id] {
        // Display doesn't apply to paint servers, which are never rendered themselves.
        return .gradient(gradientPaint(of: server, context: context, opacity: opacity))
      } else if let pattern = base.patterns[id] {
        // A cycle of patterns stops the pattern, which paints black.
        var references = references
        if references.insert(pattern: id) {
          let frame = await frame(of: element, context: context, path: path, guard: references)
          return .pattern(
            await patternPaint(
              pattern, frame: frame, opacity: opacity, context: context, mode: mode, guard: references,
              instance: instance + [element.base.elementID]))
        }
      }
      return .color(CGColor.opaqueBlack)
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
  private func strokeStyle(of element: any SVGDrawableElement, context: ResolveContext) -> StrokeStyle? {
    let style = element.style
    let color: CGColor?
    switch style.resolved(style.stroke) {
    case .none:
      return nil
    case .url:
      color = nil
    case .color(let strokeColor):
      color = strokeColor.toCGColor(opacity: style.strokeOpacity) ?? CGColor.transparent
    case .currentColor:
      preconditionFailure("currentColor is resolved")
    }
    return StrokeStyle(
      color: color,
      dashes: style.strokeDasharray.contains { $0 > 0 } ? style.strokeDasharray : nil,
      dashOffset: style.strokeDashoffset,
      width: style.strokeWidth.value(context: context, mode: .other),
      cap: style.strokeLinecap,
      join: style.strokeLinejoin,
      miterLimit: style.strokeMiterlimit)
  }
}
