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
  /// The elements in masks whose masks close cycles of masks, which they're drawn without.
  let cyclicMasks: Set<ElementID>
  /// Reads the files that the document references.
  let resources: ExternalResourceLoader
  /// The images that the `<image>` elements show, read once for the tree.
  let images = LoadedImageCollector()
  /// The documents in other files that the `<use>` elements show, read once for the tree and the builders of those
  /// documents.
  let documents: ExternalDocumentCollector
  /// The builder of the document of the `<use>` element that shows an element of this document, where this is the
  /// builder of another file, or `nil`.
  let outer: OuterBuilder?
  /// The files of the documents that show this document through `<use>` elements, and of this document last, which
  /// stop a document from showing itself again.
  let documentChain: [URL]
  /// How the root element is placed in the rectangle of the `<image>` element that shows the document as an SVG
  /// image, or `nil` if the document isn't an image.
  private let imageFit: PreserveAspectRatio?
  /// The view box that the `<view>` element that the URL of an SVG image names gives its root element instead of its
  /// own, or `nil`.
  private let imageViewBox: CGRect?
  /// How many SVG images the document is in, which limits the images in images.
  let imageDepth: Int

  /// The deepest SVG image in SVG images that is drawn. Each image is a document of its own, so the limit keeps
  /// images that show themselves again and again from making too many.
  static let maxImageDepth = 3

  /// - Parameters:
  ///   - previous: The nodes of the render tree of the document at another time, for the same rectangle, scale and
  ///     fit, which the nodes of elements that make the same nodes at every time reuse.
  ///   - resources: Reads the files that the document references. By default, none is read.
  package init(
    base: SVGBaseContext, viewPort: CGRect, scale: CGFloat, reusing previous: RenderNodeCache = .init(),
    resources: ExternalResourceLoader = .none
  ) {
    self.init(
      base: base, viewPort: viewPort, scale: scale, reusing: previous, resources: resources, imageFit: nil,
      imageViewBox: nil, imageDepth: 0)
  }

  /// The builder of a document in another file that a `<use>` element of the document of a builder shows.
  ///
  /// - Parameters:
  ///   - outer: The builder of the document of the `<use>` element.
  ///   - resources: Reads the files that the document references, relative to its file.
  ///   - chain: The files of the documents that show the document, and of the document last.
  init(external base: SVGBaseContext, of outer: RenderTreeBuilder, resources: ExternalResourceLoader, chain: [URL]) {
    self.init(
      base: base, viewPort: outer.viewPort, scale: outer.scale, reusing: .init(), resources: resources, imageFit: nil,
      imageViewBox: nil, imageDepth: outer.imageDepth, documents: outer.documents, outer: OuterBuilder(outer),
      documentChain: chain)
  }

  private init(
    base: SVGBaseContext, viewPort: CGRect, scale: CGFloat, reusing previous: RenderNodeCache,
    resources: ExternalResourceLoader, imageFit: PreserveAspectRatio?, imageViewBox: CGRect?, imageDepth: Int,
    documents: ExternalDocumentCollector = .init(), outer: OuterBuilder? = nil, documentChain: [URL]? = nil
  ) {
    self.base = base
    self.viewPort = viewPort
    self.scale = scale
    self.previous = previous
    self.resources = resources
    self.imageFit = imageFit
    self.imageViewBox = imageViewBox
    self.imageDepth = imageDepth
    self.documents = documents
    self.outer = outer
    self.documentChain = documentChain ?? resources.resolvedBaseURL.map { [$0] } ?? []
    cyclicMasks = Self.findCyclicMasks(in: base)
  }

  /// The render tree, or `nil` if building it is cancelled.
  package func build(fit: ContentFit) async -> RenderTree? {
    guard let svg = base.root else { return RenderTree(rootTransforms: [], root: nil) }
    let viewBox = svg.getViewBox(size: viewPort.size)
    let context = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: viewBox)
    let (width, height) = rootSize(of: svg, context: context)
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
    guard element.base.passesConditions else { return nil }
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
    case is SVGMaskElement, is SVGPatternElement, is SVGSymbolElement:
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
    // Text is laid out apart from its outline only when it has spans, or glyphs that the fonts draw in their colors.
    if let text = element as? SVGTextElement,
      !text.children.isEmpty || text.mayHaveColorGlyphs,
      let spans = text.spans(in: context),
      spans.contains(where: { $0.element !== text || !$0.colorGlyphs.isEmpty })
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
      // The filter of an element drawn as its source clips and masks its result instead.
      if mode != .filter(isRoot: true) {
        clip = await clipEffect(of: element, frame: frame, context: context, guard: references)
        mask = await maskApplication(
          of: element, frame: frame, context: context, guard: references, instance: instance)
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
        content = .image(await imagePaint(of: image, in: path.boundingBoxOfPath), stroke: stroke)
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
    let order = element.style.paintOrder
    // The fill and the stroke are painted as shapes of their own when the stroke is painted first, or the markers
    // between them.
    let parts: (fill: ShapeContent, stroke: ShapeContent)? =
      if case .vector(let fill, let stroke, let fillRule)? = content,
        order.strokesFirst || (!markers.isEmpty && order.layers[1] == .markers)
      {
        (.vector(fill: fill, stroke: nil, fillRule: fillRule), .vector(fill: nil, stroke: stroke, fillRule: fillRule))
      } else {
        nil
      }
    // `shape-rendering` applies to shapes, and not to text or images.
    let antialiases =
      element is SVGTextElement || element is SVGImageElement ? true : element.style.shapeRendering.antialiases
    guard !markers.isEmpty || parts != nil else {
      return .shape(
        ShapeNode(
          id: id, transform: transform, geometry: geometry, clip: clip, mask: mask, opacity: opacity(of: element, mode: mode),
          content: content, antialiases: antialiases, blendMode: blendMode(of: element, mode: mode)))
    }
    // The shape and the markers are drawn in the paint order, with the effects of the shape.
    var shapeCount = 0
    func shape(_ content: ShapeContent?) -> RenderNode {
      defer { shapeCount += 1 }
      return .shape(
        ShapeNode(
          id: partID(id, part: shapeCount), transform: .identity, geometry: geometry, clip: nil, mask: .none,
          opacity: 1, content: content, antialiases: antialiases))
    }
    var children = [RenderNode]()
    for layer in order.layers {
      switch (layer, parts) {
      case (.markers, _): children += markers
      case (.fill, let parts?): children.append(shape(parts.fill))
      case (.stroke, let parts?): children.append(shape(parts.stroke))
      case (.fill, nil): children.append(shape(content))
      case (.stroke, nil): break
      }
    }
    let groupMask: MaskEffect? = if case .mask(let effect) = mask { effect } else { nil }
    return .group(
      GroupNode(
        id: id, transform: transform, opacity: opacity(of: element, mode: mode), clip: clip, mask: groupMask, children: children,
        blendMode: blendMode(of: element, mode: mode)))
  }

  /// The mask of an element with its bounds, where a line that has a mask and no area clips everything.
  func maskApplication(
    of element: any SVGDrawableElement, frame: CGRect, context: ResolveContext, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> MaskApplication {
    let lineWidth = element.style.strokeWidth.value(context: context, mode: .other)
    if self.mask(of: element) != nil, element.type == .line, frame.width == lineWidth || frame.height == lineWidth {
      return .clipToZero
    }
    let effect = await maskEffect(
      self.mask(of: element), frame: frame, context: context, guard: references,
      instance: instance + [element.base.elementID])
    return effect.map { .mask($0) } ?? .none
  }

  /// The opacity of an element, which the filter of an element drawn as its source applies to its result instead.
  private func opacity(of element: some SVGDrawableElement, mode: DrawMode) -> CGFloat {
    mode == .filter(isRoot: true) ? 1 : element.opacity
  }

  /// How an element blends with what's behind it, which the filter of an element drawn as its source does instead.
  private func blendMode(of element: some SVGElement, mode: DrawMode) -> CGBlendMode {
    mode == .filter(isRoot: true) ? .normal : element.style.mixBlendMode.cgBlendMode
  }

  /// The identity of a part of the shape of an element that's painted as shapes of its own: the first part has the
  /// identity of the element, and the instance chain tells the others apart, as it does the copies of markers.
  func partID(_ id: RenderID, part: Int) -> RenderID {
    guard part > 0 else { return id }
    return RenderID(element: id.element, instance: id.instance + [id.element, ElementID(rawValue: Int.min + part)])
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
    let isFilterRoot = mode == .filter(isRoot: true)
    let clip = isFilterRoot ? nil : await clipEffect(of: text, frame: frame, context: context, guard: references)
    let mask =
      isFilterRoot
      ? nil
      : await maskEffect(
        self.mask(of: text), frame: frame, context: context, guard: references,
        instance: instance + [text.base.elementID])
    let transform =
      mode != .filter(isRoot: true)
      ? await transform(of: text, context: context, frame: frame, guard: references) : .identity
    // The nodes of the shapes, with the spans that each one is in.
    var children = [(node: RenderNode, spans: [any SVGDrawableElement])]()
    for span in spans {
      let element = span.element
      let context = context.styled(by: element)
      var contents: [ShapeContent?] = [nil]
      if element.style.visibility == .visible {
        let fill = await fillPaint(
          of: element, path: span.path, context: context, mode: mode, guard: references, instance: instance)
        let stroke = await stroke(
          of: element, path: span.path, context: context, mode: mode, guard: references, instance: instance)
        // A stroke that's painted first is a shape of its own, before the fill.
        contents =
          element.style.paintOrder.strokesFirst
          ? [
            .vector(fill: nil, stroke: stroke, fillRule: element.pathFillRule),
            .vector(fill: fill, stroke: nil, fillRule: element.pathFillRule),
          ] : [.vector(fill: fill, stroke: stroke, fillRule: element.pathFillRule)]
      }
      let id = renderID(of: element, instance: instance)
      for (part, content) in contents.enumerated() {
        children.append(
          (
            .shape(
              ShapeNode(
                id: partID(id, part: part), transform: .identity,
                geometry: Geometry(path: RenderPath(span.path), frame: frame), clip: nil, mask: .none, opacity: 1,
                content: content)), span.spans
          ))
      }
      // The glyphs that the fonts draw in their colors are drawn after the other glyphs, without the paints of the
      // element: a fill that isn't `none` draws them with its opacity, as browsers draw them.
      if !span.colorGlyphs.isEmpty {
        let bounds = CGMutablePath()
        for glyph in span.colorGlyphs { bounds.addRect(glyph.bounds) }
        let draws = element.style.visibility == .visible && element.style.fill != .none
        children.append(
          (
            .shape(
              ShapeNode(
                id: partID(id, part: 1 << 17), transform: .identity,
                geometry: Geometry(path: RenderPath(bounds), frame: frame), clip: nil, mask: .none, opacity: 1,
                content: draws ? .colorGlyphs(span.colorGlyphs, opacity: element.style.fillOpacity) : nil)),
            span.spans
          ))
      }
    }
    // The shapes of each span with an opacity, a clip path, a mask, a filter or a blend mode, which SVG 2 applies to
    // spans as to graphics elements, are a group of their own, from the innermost spans out, at the place of their
    // first shape. Their units are the bounds of the whole text, as the units of their paints are.
    let spanMode: DrawMode = mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode
    var effected = [any SVGDrawableElement]()
    for span in spans {
      for element in span.spans where hasEffect(element) && !effected.contains(where: { $0 === element }) {
        effected.append(element)
      }
    }
    for element in effected.reversed() {
      let members = children.indices.filter { index in children[index].spans.contains { $0 === element } }
      guard let first = members.first else { continue }
      let outer = Array(children[first].spans.prefix { $0 !== element })
      let node = await effectNode(
        of: element, children: members.map { children[$0].node }, frame: frame, context: context, mode: spanMode,
        guard: references, instance: instance)
      for index in members.reversed() {
        children.remove(at: index)
      }
      if let node {
        children.insert((node, outer), at: first)
      }
    }
    return .group(
      GroupNode(
        id: renderID(of: text, instance: instance), transform: transform, opacity: opacity(of: text, mode: mode), clip: clip,
        mask: mask, children: children.map(\.node), blendMode: blendMode(of: text, mode: mode)))
  }

  /// Whether a span has an opacity, a clip path, a mask, a filter or a blend mode, which make its shapes a group.
  private func hasEffect(_ span: any SVGDrawableElement) -> Bool {
    span.opacity != 1 || span.clipPath != nil || mask(of: span) != nil || span.filter != nil
      || span.style.mixBlendMode != .normal
  }

  /// The shapes of a span in a group with its opacity, clip path, mask, filter and blending, whose units are the
  /// bounds of the whole text, or `nil` if its filter draws nothing.
  ///
  /// - Parameter context: The context of the text.
  private func effectNode(
    of span: any SVGDrawableElement, children: [RenderNode], frame: CGRect, context: ResolveContext, mode: DrawMode,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> RenderNode? {
    let context = context.styled(by: span)
    let id = renderID(of: span, instance: instance)
    let clip = await clipEffect(span.clipPath, frame: frame, context: context, guard: references)
    let mask = await maskEffect(
      self.mask(of: span), frame: frame, context: context, guard: references, instance: instance + [span.base.elementID])
    if let functions = span.filter {
      switch filterElements(of: functions, guard: references) {
      case .none:
        break
      case .drawsNothing:
        return nil
      case .filters(let filters):
        let source = RenderNode.group(
          GroupNode(id: partID(id, part: functions.count), transform: .identity, opacity: 1, clip: nil, mask: nil, children: children))
        return await applyingFilters(
          functions, filters: filters, of: span, to: source, frame: frame, transform: .identity, clip: clip,
          mask: mask.map { .mask($0) } ?? .none, filterContext: context, functionContext: context, guard: references,
          id: id, instance: instance)
      }
    }
    return .group(
      GroupNode(
        id: id, transform: .identity, opacity: opacity(of: span, mode: mode), clip: clip, mask: mask, children: children,
        blendMode: blendMode(of: span, mode: mode)))
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
    if mode != .filter(isRoot: true), group.clipPath != nil || self.mask(of: group) != nil {
      let groupFrame = await self.frame(of: group, context: context, path: nil, guard: references)
      clip = await clipEffect(of: group, frame: groupFrame, context: context, guard: references)
      mask = await maskEffect(
        self.mask(of: group), frame: groupFrame, context: context, guard: references,
        instance: instance + [group.base.elementID])
      frame = groupFrame
    }
    let transform =
      mode != .filter(isRoot: true)
      ? await transform(of: group, context: context, frame: frame, guard: references) : .identity
    let childMode = mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode
    var children = [RenderNode]()
    for child in renderedChildren(of: group) {
      guard let child = child as? (any SVGDrawableElement) else { continue }
      if let node = await node(of: child, context: context, mode: childMode, guard: references, instance: instance) {
        children.append(node)
      }
    }
    return .group(
      GroupNode(
        id: renderID(of: group, instance: instance), transform: transform, opacity: opacity(of: group, mode: mode), clip: clip,
        mask: mask, children: children, blendMode: blendMode(of: group, mode: mode),
        isolates: group.style.isolation == .isolate))
  }

  /// The children of a group that it renders. A `<switch>` renders only its first child whose conditional processing
  /// attributes evaluate to true, even if `display` hides that child. Its children that can't be rendered directly,
  /// such as `<defs>` and `<clipPath>`, aren't chosen, and neither are the elements that SVGUIView doesn't render,
  /// such as `<foreignObject>`, so that a later child is the fallback for them.
  private func renderedChildren(of group: SVGGroupElement) -> [any SVGElement] {
    guard group.base.name == .switch else { return group.children }
    let chosen = group.children.first { child in
      switch child {
      case is SVGDefsElement, is SVGMaskElement, is SVGPatternElement, is SVGSymbolElement, is SVGFilterElement:
        false
      case let child as any SVGDrawableElement:
        child.base.passesConditions
      default:
        false
      }
    }
    return chosen.map { [$0] } ?? []
  }

  private func viewportNode(
    of svg: SVGSVGElement, context: ResolveContext, mode: DrawMode, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> RenderNode {
    let context = context.styled(by: svg)
    let id = renderID(of: svg, instance: instance)
    let isRoot = svg.base.elementID == base.root?.base.elementID
    // The viewport of a symbol has no transform of its own, as SVG 1.1 has, and as WebKit draws it.
    let transform =
      mode != .filter(isRoot: true) && svg.base.name != .symbol
      ? await transform(of: svg, context: context, frame: nil, guard: references) : .identity
    var (translation, layout) = viewport(of: svg, context: context, isRoot: isRoot)
    // The filter of the element moves the content to the viewport and to the position of the element instead.
    if mode == .filter(isRoot: true) {
      translation = .identity
      layout = layout.map { ViewportLayout(viewBoxTransform: .identity, rect: $0.rect, context: $0.context) }
    }
    guard let layout else {
      return .viewport(
        ViewportNode(id: id, transform: transform, translation: translation, opacity: opacity(of: svg, mode: mode), content: nil))
    }
    let inner = layout.context
    var overflowClip: CGRect?
    // The view shows the viewport of the root element, which clips it whatever its overflow is. The overflow of the
    // `<image>` element that shows an SVG image clips the image instead.
    switch isRoot ? (imageFit == nil ? .hidden : .visible) : svg.overflow {
    case .visible, .auto:
      break
    default:
      if svg.width != nil, svg.height != nil {
        overflowClip = layout.rect
      }
    }
    let references = beginsLevel(mode) ? references.beginning([.clipPaths, .masks]) : references
    // The filter of the element clips and masks its result instead.
    let isFilterRoot = mode == .filter(isRoot: true)
    let clip = isFilterRoot ? nil : await clipEffect(svg.clipPath, frame: inner.viewBox, context: inner, guard: references)
    let mask =
      isFilterRoot
      ? nil
      : await maskEffect(
        self.mask(of: svg), frame: inner.viewBox, context: inner, guard: references,
        instance: instance + [svg.base.elementID])
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
        id: id, transform: transform, translation: translation, opacity: opacity(of: svg, mode: mode),
        content: ViewportContent(
          viewBoxTransform: layout.viewBoxTransform, overflowClip: overflowClip, clip: clip, mask: mask,
          children: children), blendMode: blendMode(of: svg, mode: mode), isolates: svg.style.isolation == .isolate))
  }

  /// The content of a viewport, which has an area.
  struct ViewportLayout {
    /// The transform from the coordinates of the content to the viewport.
    let viewBoxTransform: CGAffineTransform
    /// The viewport in the coordinates of its content.
    let rect: CGRect
    /// The context of the content.
    let context: ResolveContext
  }

  /// The translation of a viewport by `x` and `y`, and its content, or `nil` if it has no area, in a context styled by
  /// the `svg` element. The view places the viewport of the root element, so its `x` and `y` don't apply.
  ///
  /// The root element of an SVG image fills the rectangle of the `<image>` element, which is the viewport of the
  /// builder: the `preserveAspectRatio` that ``imageFit(of:root:)`` chose places its view box there, or the box of
  /// its width and height if it has no view box.
  func viewport(
    of svg: SVGSVGElement, context: ResolveContext, isRoot: Bool
  ) -> (translation: CGAffineTransform, layout: ViewportLayout?) {
    if isRoot, let imageFit {
      let viewBox = viewBoxOfImage(svg)
      guard viewBox.width > 0, viewBox.height > 0, viewPort.width > 0, viewPort.height > 0 else {
        return (.identity, nil)
      }
      let transform = imageFit.getTransform(viewBox: viewBox, size: viewPort.size)
      let rect = CGRect(origin: .zero, size: viewPort.size).applying(transform.inverted())
      return (
        CGAffineTransform(translationX: viewPort.minX, y: viewPort.minY),
        ViewportLayout(viewBoxTransform: transform, rect: rect, context: context.with(viewBox: viewBox))
      )
    }
    let translation: CGAffineTransform =
      if isRoot {
        .identity
      } else {
        CGAffineTransform(
          translationX: (svg.x ?? .pixel(0)).value(context: context, mode: .width),
          y: (svg.y ?? .pixel(0)).value(context: context, mode: .height))
      }
    let (width, height) =
      isRoot
      ? rootSize(of: svg, context: context)
      : (
        (svg.width ?? .percent(100)).value(context: context, mode: .width),
        (svg.height ?? .percent(100)).value(context: context, mode: .height)
      )
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
    if !isFilterRoot, use.clipPath != nil || self.mask(of: use) != nil {
      let useFrame = await self.frame(of: use, context: context, path: nil, guard: references)
      clip = await clipEffect(use.clipPath, frame: useFrame, context: context, guard: references)
      mask = await maskEffect(
        self.mask(of: use), frame: useFrame, context: context, guard: references,
        instance: instance + [use.base.elementID])
      frame = useFrame
    }
    let transform =
      isFilterRoot ? .identity : await transform(of: use, context: context, frame: frame, guard: references)
    let content = await withReferencedElement(of: use, context: context, guard: references) { referenced in
      UseInstance(
        translation: translation(of: use, context: context), opacity: opacity(of: use, mode: mode),
        content: await referenced.builder.node(
          of: referenced.element, context: referenced.context, mode: .normal, guard: referenced.references,
          instance: instance + [use.base.elementID] + referenced.instance))
    }
    return .use(
      UseNode(
        id: renderID(of: use, instance: instance), transform: transform, clip: clip, mask: mask, instance: content,
        blendMode: blendMode(of: use, mode: mode), isolates: use.style.isolation == .isolate))
  }

  // MARK: - `<use>`

  /// Calls `body` with the element that the `<use>` element shows, with its computed values computed again with
  /// the `<use>` element as its parent, and the guard with the elements added, or returns `nil` if there is none or
  /// showing it would make a cycle.
  ///
  /// An element of another document is built by the builder of that document, in a context whose references find
  /// its elements. Its copy is styled by the style sheets of that document, and inherits from the `<use>` element,
  /// whose paints and markers stay references of the document of the `<use>` element. The other document is shown
  /// without animations, at time zero, as an SVG image is.
  func withReferencedElement<T>(
    of use: SVGUseElement, context: ResolveContext, guard references: ReferenceGuard,
    _ body: (ReferencedElement) async -> T
  ) async -> T? {
    // A `<use>` element follows its reference also where no level of `<use>` elements has begun, such as in the
    // bounds of a group or in a clip path of a group, and the level stops a cycle from there.
    var references = references.uses == nil ? references.beginning(.uses) : references
    _ = references.insert(use: use.index)
    let builder: RenderTreeBuilder
    let element: any SVGDrawableElement
    if let parentId = use.parentId, let found = base[parentId] {
      builder = self
      element = found
    } else if let href = use.externalHref, let external = await externalBuilder(for: href.url),
      let found = external.base[href.id]
    {
      builder = external
      element = found
    } else {
      return nil
    }
    guard references.insert(use: element.index), !element.contains(index: use.index) else { return nil }
    let isExternal = builder.base.root !== base.root
    // The copy is styled in a tree of its own, where selectors don't see the ancestors of the element.
    let restyled = element.restyled(
      parent: isExternal ? OuterReference.marking(use.style) : use.style, root: base.root?.style ?? use.style,
      animations: !isExternal && base.isAnimated ? base.animations : nil,
      userAgentDeclarations: element is SVGSVGElement ? CascadedValues.userAgentDeclarationsOfInstanceRoot : [],
      instance: builder.base.instanceStyles.cascades(ofCopyOf: element.base.elementID))
    let shown: any SVGDrawableElement
    if let svg = restyled as? SVGSVGElement {
      shown = svg.sized(width: use.width, height: use.height)
    } else if let symbol = restyled as? SVGSymbolElement {
      // A symbol shows its children in a viewport, as an `<svg>` element with its attributes does.
      shown = SVGSVGElement(base: symbol.base, contents: symbol.children).sized(width: use.width, height: use.height)
    } else if let restyled = restyled as? (any SVGDrawableElement) {
      shown = restyled
    } else {
      return nil
    }
    return await body(
      ReferencedElement(
        element: shown, references: references, builder: builder,
        context: isExternal ? context.with(base: builder.base) : context,
        instance: isExternal ? [builder.externalDocumentMarker] : []))
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
    case let image as SVGImageElement:
      return await imageRect(of: image, context: context).map { CGPath(rect: $0, transform: nil) }
    case let shape as any ShapeGeometry:
      return shape.path(in: context)
    case let use as SVGUseElement:
      // An element with display none isn't rendered, also where a use element references it.
      let path = await withReferencedElement(of: use, context: context, guard: references) { referenced in
        referenced.element.display == CSSDisplay.none
          ? nil
          : await referenced.builder.path(
            of: referenced.element, context: referenced.context.styled(by: referenced.element),
            guard: referenced.references)
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
    if let svg = element as? SVGSVGElement, svg.base.elementID == base.root?.base.elementID {
      return context.transform(of: svg.style, box: rootBox(of: svg, context: context))
    }
    let transform = await transform(of: element.style, context: context) { box in
      await referenceBox(box, of: element, context: context, frame: frame, guard: references)
    }
    // The motion of `<animateMotion>` applies after the transform, in the coordinates of the parent.
    return transform.concatenating(element.style.motion)
  }

  /// The reference box of an element for transforms and basic shapes, in a context styled by the element.
  ///
  /// - Parameter frame: The bounds of the element, if they're known, which are its `fill-box`.
  func referenceBox(
    _ box: TransformBox, of element: any SVGDrawableElement, context: ResolveContext, frame: CGRect?,
    guard references: ReferenceGuard
  ) async -> CGRect {
    // The box of `view-box` starts at the origin of user space, also for a `viewBox` that doesn't.
    if box == .viewBox { return CGRect(origin: .zero, size: context.viewBoxSize) }
    if box == .fillBox || box == .contentBox, let frame { return frame }
    let path = await path(of: element, context: context, guard: references)
    return await self.frame(
      of: element, context: context, path: path, includesStroke: box == .strokeBox || box == .borderBox,
      guard: references)
  }

  /// The transform of computed values about their transform origin.
  ///
  /// - Parameter reference: The reference box of the element for `fill-box` or `stroke-box`, which is found only for
  ///   a transform that isn't `none`.
  func transform(
    of style: ComputedStyle, context: ResolveContext, reference: (TransformBox) async -> CGRect
  ) async -> CGAffineTransform {
    guard !style.transform.functions.isEmpty else { return .identity }
    // The box of `view-box` starts at the origin of user space, also for a `viewBox` that doesn't.
    let box =
      style.transformBox == .viewBox ? CGRect(origin: .zero, size: context.viewBoxSize) : await reference(style.transformBox)
    return context.transform(of: style, box: box)
  }

  /// The box of CSS layout of the root element, which is the reference box of its transform for every
  /// `transform-box`: its viewport, in the coordinates that the view or the `<image>` element places it in. Its
  /// transform applies outside the transform of its view box.
  private func rootBox(of svg: SVGSVGElement, context: ResolveContext) -> CGRect {
    if imageFit != nil { return viewPort }
    let (width, height) = rootSize(of: svg, context: context)
    return CGRect(x: 0, y: 0, width: width, height: height)
  }

  /// The size of the root element in the view. Without a view box, it's the box that ``SVGSVGElement/getViewBox(size:)``
  /// finds, whose percentages and viewport units are of the view, since its content is in that box: resolving them in
  /// the content would make them a part of themselves.
  private func rootSize(of svg: SVGSVGElement, context: ResolveContext) -> (width: CGFloat, height: CGFloat) {
    if svg.viewBox == nil {
      let box = svg.getViewBox(size: viewPort.size)
      return (box.width, box.height)
    }
    return (
      (svg.width ?? .percent(100)).value(context: context, mode: .width),
      (svg.height ?? .percent(100)).value(context: context, mode: .height)
    )
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
      return await frame(
        of: renderedChildren(of: group), context: context, includesStroke: includesStroke, guard: references) ?? .zero
    case let svg as SVGSVGElement:
      // The bounds of the children, each with its transform, in the coordinates that the viewport is placed in.
      let (translation, layout) = viewport(
        of: svg, context: context, isRoot: svg.base.elementID == base.root?.base.elementID)
      guard let layout,
        let frame = await frame(
          of: svg.children, context: layout.context, includesStroke: includesStroke, guard: references)
      else { return .zero }
      return frame.applying(layout.viewBoxTransform.concatenating(translation))
    case let use as SVGUseElement:
      let frame = await withReferencedElement(of: use, context: context, guard: references) { referenced in
        let builder = referenced.builder
        let context = referenced.context.styled(by: referenced.element)
        return await builder.frame(
          of: referenced.element, context: context,
          path: await builder.path(of: referenced.element, context: context, guard: referenced.references),
          includesStroke: includesStroke, guard: referenced.references)
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
      guard let child = child as? (any SVGDrawableElement), child.base.passesConditions else { continue }
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
      // A paint that the copy of an element of another document inherits from the `<use>` element that shows it
      // names a paint server of the document of the `<use>` element.
      let owner = owner(ofReference: id)
      if owner.id != id {
        return await owner.builder.paint(
          .url(owner.id, fallback: fallback), opacity: opacity, of: element, path: path,
          context: context.with(base: owner.builder.base), mode: mode, guard: references, instance: instance)
      }
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
    case .currentColor, .expression:
      preconditionFailure("currentColor is resolved")
    }
  }

  /// The gradient with the attributes of the gradients that it references, which it doesn't have.
  ///
  /// A reference to a gradient that's already been followed ends the references, and the gradient has the
  /// attributes of the ones before it.
  private func gradientPaint(
    of server: any SVGGradientServer, context: ResolveContext, opacity: CGFloat
  ) -> GradientPaint? {
    var merged = server
    var followed: Set<String> = server.id.map { [$0] } ?? []
    while let id = merged.parentId, followed.insert(id).inserted, let parent = base.pservers[id] {
      merged = merged.merged(other: parent)
    }
    return merged.paint(context: context, opacity: opacity)
  }

  /// The image of an `<image>` element placed in its rectangle by its `preserveAspectRatio`, or `nil` if its data
  /// isn't an image, or is an SVG image deeper in SVG images than the ones that are drawn.
  ///
  /// The data is a data URL, or a file that the loader reads. It's decoded as a bitmap, or else parsed as an SVG
  /// image: a document of its own, without animations, at time zero, which can't reference anything outside it.
  private func imagePaint(of element: SVGImageElement, in rect: CGRect) async -> ImagePaint? {
    guard let image = await loadedImage(of: element) else { return nil }
    let clips =
      switch element.style.overflow {
      case .visible, .auto: false
      default: true
      }
    return await imagePaint(
      image: image, preserveAspectRatio: element.preserveAspectRatio, clips: clips,
      interpolates: element.style.imageRendering.interpolates, in: rect)
  }

  /// An image of data, a bitmap or an SVG image, placed in a rectangle by its `preserveAspectRatio`, or `nil` if the
  /// data isn't an image.
  ///
  /// - Parameters:
  ///   - clips: Whether the rectangle clips the image where it overflows the rectangle.
  ///   - interpolates: Whether a bitmap is interpolated where it's scaled.
  func imagePaint(
    data: Data, preserveAspectRatio: PreserveAspectRatio, clips: Bool, interpolates: Bool, in rect: CGRect
  ) async -> ImagePaint? {
    guard let image = loadImage(data: data, fragment: nil) else { return nil }
    return await imagePaint(
      image: image, preserveAspectRatio: preserveAspectRatio, clips: clips, interpolates: interpolates, in: rect)
  }

  /// The `preserveAspectRatio` that places an SVG image in the rectangle of an element that shows it.
  ///
  /// It's the one of the root element of the image, if the root element has the attribute, unless the one of the
  /// element that shows the image is `none`, which stretches the image. A root element without the attribute is
  /// placed by the one of the element that shows the image.
  ///
  /// - Note: This differs from SVG 2, which says that the attribute of the root element "must be ignored", so
  ///   that the one of the element that shows the image always places the image. Chrome and Safari place the image
  ///   by the attribute of its root element, and a reftest of the web platform tests,
  ///   `svg/embedded/image-fractional-width-vertical-fidelity.svg`, expects that, so SVGUIView follows them where the
  ///   root element has the attribute. Firefox follows the specification. Where the root element doesn't have the
  ///   attribute, Chrome and Safari place the image by the default of the root element, `xMidYMid meet`: there
  ///   SVGUIView follows the specification, as `coords-viewattr-04-f` of the SVG 1.1 test suite expects.
  private static func imageFit(of preserveAspectRatio: PreserveAspectRatio, root: SVGSVGElement) -> PreserveAspectRatio {
    if case .none = preserveAspectRatio { return preserveAspectRatio }
    return root.preserveAspectRatio ?? preserveAspectRatio
  }

  /// An image, a bitmap or an SVG image, placed in a rectangle by its `preserveAspectRatio`, or `nil` if an SVG image
  /// has no view box with an area. An SVG image is placed by the `preserveAspectRatio` that
  /// ``imageFit(of:root:)`` chooses.
  private func imagePaint(
    image: LoadedImage, preserveAspectRatio: PreserveAspectRatio, clips: Bool, interpolates: Bool, in rect: CGRect
  ) async -> ImagePaint? {
    let content: ImageContent
    let viewBox: CGRect
    var preserveAspectRatio = preserveAspectRatio
    switch image.content {
    case .bitmap(let bitmap):
      content = .bitmap(bitmap)
      viewBox = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
    case .document(let document):
      guard let svg = document.root else { return nil }
      preserveAspectRatio = Self.imageFit(of: preserveAspectRatio, root: svg)
      let builder = RenderTreeBuilder(
        base: document, viewPort: rect, scale: scale, reusing: .init(), resources: .none,
        imageFit: preserveAspectRatio, imageViewBox: image.viewBox, imageDepth: imageDepth + 1)
      let context = ResolveContext(
        base: document, viewPort: rect, scale: scale, viewBox: CGRect(origin: .zero, size: rect.size))
      guard
        let node = await builder.node(of: svg, context: context, mode: .root, guard: ReferenceGuard(), instance: [])
      else { return nil }
      content = .document(node)
      viewBox = builder.viewBoxOfImage(svg)
      guard viewBox.width > 0, viewBox.height > 0 else { return nil }
    }
    let placed = viewBox.applying(preserveAspectRatio.getTransform(viewBox: viewBox, size: rect.size))
      .offsetBy(dx: rect.minX, dy: rect.minY)
    let clip: CGRect? = clips && !rect.contains(placed) ? rect : nil
    return ImagePaint(content: content, rect: placed, clip: clip, interpolates: interpolates)
  }

  /// The view box of the root element of an SVG image: the one of the `<view>` that the URL of the image names, its
  /// own, or the box of its width and height if it has none. The percentages of the width and the height are of the
  /// rectangle of the `<image>` element.
  private func viewBoxOfImage(_ svg: SVGSVGElement) -> CGRect {
    imageViewBox ?? svg.getViewBox(size: viewPort.size)
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
