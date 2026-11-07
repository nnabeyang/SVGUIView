import CoreGraphics
import Foundation

extension RenderTreeBuilder {
  enum Filtering {
    /// The element has no filter.
    case none
    /// The node of the element with its filter, or `nil` for a filter element without children, which draws
    /// nothing.
    case filtered(RenderNode?)
  }

  /// Applies the filters of an element, if it has any, one after another: the first one filters the element, and
  /// each of the others filters the result of the one before it.
  ///
  /// - Parameters:
  ///   - context: The context of the parent of the element.
  ///   - references: The guard that the bounds of the element are found with.
  func filtering(
    of element: any SVGDrawableElement, context: ResolveContext, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> Filtering {
    guard let functions = element.filter else { return .none }
    let filters: [String: SVGFilterElement]
    switch filterElements(of: functions, guard: references) {
    case .none: return .none
    case .drawsNothing: return .filtered(nil)
    case .filters(let elements): filters = elements
    }
    // The source keeps the filters of the `feImage` primitives that draw the element.
    var sourceReferences = ReferenceGuard()
    sourceReferences.filters = references.filters
    let elementContext = context.styled(by: element)
    let path = await path(of: element, context: elementContext, guard: references)
    var frame = await frame(of: element, context: elementContext, path: path, guard: references)
    // The filter draws the element in a context of its own, with the viewBox and nothing else of the context.
    let sourceContext = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: context.viewBox)
    let source = await nodeWithoutFilter(
      of: element, context: sourceContext, mode: .filter(isRoot: true), guard: sourceReferences, instance: instance)
    var transform = await transform(of: element, context: elementContext, frame: frame, guard: references)
    // The filter of an `<svg>` element applies in the coordinates of its content, as Chrome and Firefox draw it: the
    // filter region and the values of the primitives are resolved there, and the result moves to the viewport and
    // the position of the element after the filter.
    var filterContext = context
    var functionContext = elementContext
    var clip: ClipPathEffect?
    var mask = MaskApplication.none
    if let svg = element as? SVGSVGElement {
      let (translation, layout) = viewport(
        of: svg, context: elementContext, isRoot: svg.base.elementID == base.root?.base.elementID)
      // A viewport without area draws nothing.
      guard let layout else { return .filtered(nil) }
      frame = await self.frame(of: svg.children, context: layout.context, guard: references) ?? .zero
      filterContext = layout.context
      functionContext = layout.context
      // The viewport of a symbol has no transform of its own, as its node has none.
      let svgTransform =
        svg.base.name != .symbol
        ? await self.transform(of: svg, context: elementContext, frame: nil, guard: references) : .identity
      transform = layout.viewBoxTransform.concatenating(translation).concatenating(svgTransform)
      // The clip path and the mask of an `<svg>` element are in the coordinates of its content too, with the viewBox
      // as its bounds, as its node has them.
      let inner = layout.context
      clip = await clipEffect(svg.clipPath, frame: inner.viewBox, context: inner, guard: references)
      if let effect = await maskEffect(
        self.mask(of: svg), frame: inner.viewBox, context: inner, guard: references,
        instance: instance + [svg.base.elementID])
      {
        mask = .mask(effect)
      }
    } else {
      clip = await clipEffect(of: element, frame: frame, context: elementContext, guard: references)
      mask = await maskApplication(
        of: element, frame: frame, context: elementContext, guard: references, instance: instance)
    }
    return .filtered(
      await applyingFilters(
        functions, filters: filters, of: element, to: source, frame: frame, transform: transform, clip: clip,
        mask: mask, filterContext: filterContext, functionContext: functionContext, guard: references,
        id: RenderID(element: element.base.elementID, instance: instance), instance: instance))
  }

  /// The filter elements that the filters of an element reference.
  enum FilterElements {
    /// A reference to something that isn't a filter element makes the element have no filters.
    case none
    /// A filter element without children, or one that the element is drawn by already, draws nothing.
    case drawsNothing
    case filters([String: SVGFilterElement])
  }

  /// The filter elements of the filters of an element, or what the element draws without them.
  func filterElements(of functions: [SVGFilterFunction], guard references: ReferenceGuard) -> FilterElements {
    var filters = [String: SVGFilterElement]()
    for case .url(let id) in functions {
      guard let filter = base.filters[id] else { return .none }
      // A filter element without children draws nothing, which nothing after it can draw from.
      guard !filter.knownChildren.isEmpty else { return .drawsNothing }
      filters[id] = filter
    }
    // A `feImage` of a filter that draws an element with the filter again draws nothing of that element.
    guard filters.keys.allSatisfy({ !references.filters.contains($0) }) else { return .drawsNothing }
    return .filters(filters)
  }

  /// Applies filters to the source of an element one after another, where the last one draws the result with the
  /// transform, the clip path, the mask, the opacity and the blending of the element, and the others draw theirs
  /// into the source of the next one as they are.
  ///
  /// - Parameters:
  ///   - frame: The bounds of the element, which the units of the filters are of.
  ///   - filterContext: The context that the filter regions and the primitives are resolved in.
  ///   - functionContext: The context that the filter functions are resolved in.
  ///   - references: The guard that the element is drawn with.
  func applyingFilters(
    _ functions: [SVGFilterFunction], filters: [String: SVGFilterElement], of element: any SVGDrawableElement,
    to source: RenderNode?, frame: CGRect, transform: CGAffineTransform, clip: ClipPathEffect?, mask: MaskApplication,
    filterContext: ResolveContext, functionContext: ResolveContext, guard references: ReferenceGuard, id: RenderID,
    instance: [ElementID]
  ) async -> RenderNode? {
    // The `feImage` primitives of the filters add the filters to the filters that draw the element, so that the same
    // filter on a child of the element is no cycle.
    var imageReferences = ReferenceGuard()
    imageReferences.filters = references.filters.union(filters.keys)
    var source = source
    for (i, function) in functions.enumerated() {
      let isLast = i == functions.count - 1
      let effect: FilterEffect?
      if case .url(let filterID) = function, let filter = filters[filterID] {
        let region = effectRect(of: filter, frame: frame, context: filterContext)
        effect = FilterEffect(
          effectRect: region, colorInterpolation: filter.colorInterpolation ?? .sRGB,
          colorInterpolationFilters: filter.colorInterpolationFilters ?? .linearRGB,
          primitives: await primitives(
            of: filter, region: region, frame: frame, context: filterContext, guard: imageReferences,
            instance: instance))
      } else {
        effect = functionEffect(
          of: function, element: element, source: source, frame: frame, context: functionContext)
      }
      guard let effect else {
        // A filter function of a source that paints nothing paints nothing.
        source = nil
        continue
      }
      source = .filtered(
        FilteredNode(
          id: partID(id, part: functions.count - 1 - i), transform: isLast ? transform : .identity, frame: frame,
          effectRect: effect.effectRect, colorInterpolation: effect.colorInterpolation,
          colorInterpolationFilters: effect.colorInterpolationFilters, opacity: isLast ? element.opacity : 1,
          primitives: effect.primitives, source: source,
          blendMode: isLast ? element.style.mixBlendMode.cgBlendMode : .normal, clip: isLast ? clip : nil,
          mask: isLast ? mask : .none))
    }
    return source
  }

  /// What a filter element or a filter function does to its source.
  struct FilterEffect {
    let effectRect: CGRect
    let colorInterpolation: SVGColorInterpolation
    let colorInterpolationFilters: SVGColorInterpolation
    let primitives: [FilterStep]
  }

  /// The steps of the primitives of a filter element, where a `feDropShadow` is the steps that it's equal to.
  ///
  /// - Parameter region: The filter region.
  ///   - references: The guard that the elements of the `feImage` primitives are drawn with.
  private func primitives(
    of filter: SVGFilterElement, region: CGRect, frame: CGRect, context: ResolveContext,
    guard references: ReferenceGuard, instance: [ElementID]
  ) async -> [FilterStep] {
    var steps = [FilterStep]()
    // The subregions of the named results, and of the primitive before, which the subregions of the primitives that
    // take them default to.
    var resultSubregions = [String: CGRect]()
    var previousSubregion: CGRect?
    /// The subregion of an input, or `nil` for a standard input, whose subregion is the filter region. A name that no
    /// primitive before has given is the result of the primitive before, as it is in the painting.
    func inputSubregion(_ input: SVGFilterInput?) -> CGRect? {
      switch input {
      case nil: previousSubregion
      case .sourceGraphic, .sourceAlpha: nil
      case .other(let name): resultSubregions[name] ?? previousSubregion
      }
    }
    for child in filter.knownChildren {
      guard let child = child as? (any SVGFilterPrimitiveElement) else { continue }
      // The attributes that the primitive doesn't have come from the union of the subregions of its inputs, or from
      // the filter region for a primitive without inputs, one with a standard input and a `feTile`.
      let inputSubregions = Self.inputs(of: child).map(inputSubregion)
      let defaultSubregion =
        inputSubregions.isEmpty || inputSubregions.contains(nil)
        ? region : inputSubregions.compactMap { $0 }.reduce(CGRect.null) { $0.union($1) }
      let subregion = subregion(
        of: child, filter: filter, frame: frame, context: context, defaultSubregion: defaultSubregion)
      // The property is inherited, so the primitive has the value of the filter element where it declares none, and
      // the initial value is linearRGB.
      let colorSpace = child.base.style.colorInterpolationFilters ?? .linearRGB
      if let shadow = child as? SVGFeDropShadowElement {
        let input = shadow.input ?? previousResult(of: &steps)
        steps += dropShadowSteps(
          of: shadow, input: input, filter: filter, region: region, subregion: subregion, frame: frame,
          context: context, colorSpace: colorSpace)
      } else if let image = child as? SVGFeImageElement {
        steps.append(
          FilterStep(
            primitive: .image(
              await imagePrimitive(
                of: image, subregion: subregion, context: context, guard: references, instance: instance)),
            subregion: subregion, result: child.result, colorSpace: colorSpace))
      } else if let tile = child as? SVGFeTileElement {
        steps.append(
          FilterStep(
            primitive: .tile(input: tile.input, tile: inputSubregion(tile.input) ?? region), subregion: subregion,
            result: child.result, colorSpace: colorSpace))
      } else {
        steps.append(
          FilterStep(
            primitive: primitive(of: child, filter: filter, frame: frame, context: context), subregion: subregion,
            result: child.result, colorSpace: colorSpace))
      }
      previousSubregion = subregion
      if let result = child.result {
        resultSubregions[result] = subregion
      }
    }
    return steps
  }

  /// The input that is the result of the primitive before, which a primitive takes without `in`: the source graphic
  /// for the first primitive, and the name of the result of the step before for the others, which gets a name that
  /// no document can give where it has none.
  private func previousResult(of steps: inout [FilterStep]) -> SVGFilterInput {
    guard let last = steps.last else { return .sourceGraphic }
    if let result = last.result { return .other(result) }
    let name = "\u{0}result\(steps.count)"
    steps[steps.count - 1] = FilterStep(
      primitive: last.primitive, subregion: last.subregion, result: name, colorSpace: last.colorSpace)
    return .other(name)
  }

  /// What a `feImage` draws, or `nil` for nothing: an image of a data URL placed in the subregion by its
  /// `preserveAspectRatio`, or an element of the document, drawn in the user space of the element with the filter
  /// moved to the origin of the subregion, as the `<use>` element that the specification likens it to, Chrome and
  /// resvg draw it.
  private func imagePrimitive(
    of image: SVGFeImageElement, subregion: CGRect, context: ResolveContext, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> ImagePrimitive? {
    switch image.source {
    case nil:
      return nil
    case .data(let data):
      return await imagePaint(
        data: data, preserveAspectRatio: image.preserveAspectRatio, clips: false,
        interpolates: image.base.style.imageRendering.interpolates, in: subregion
      ).map { .picture($0) }
    case .element(let id):
      guard let element = base[id] else { return nil }
      return await node(
        of: element, context: context, mode: .normal, guard: references, instance: instance + [image.base.elementID]
      ).map { .element($0, origin: subregion.origin) }
    }
  }

  /// The steps of a `feDropShadow`: a shadow of the flood color and opacity in the color space of the primitive,
  /// under the input.
  private func dropShadowSteps(
    of shadow: SVGFeDropShadowElement, input: SVGFilterInput, filter: SVGFilterElement, region: CGRect,
    subregion: CGRect, frame: CGRect, context: ResolveContext, colorSpace: SVGColorInterpolation
  ) -> [FilterStep] {
    let units = filter.primitiveUnits ?? .userSpaceOnUse
    var offset = CGSize(width: shadow.dx ?? 2, height: shadow.dy ?? 2)
    if units == .objectBoundingBox {
      offset = CGSize(width: offset.width * frame.width, height: offset.height * frame.height)
    }
    let deviation: GaussianBlurPrimitive.StandardDeviation =
      switch shadow.stdDeviation ?? .iso(.number(2)) {
      case .iso(let value):
        .iso(value.calculatedLength(frame: frame, context: context, mode: .other, unitType: units))
      case .hetero(let x, let y):
        .hetero(
          x: x.calculatedLength(frame: frame, context: context, mode: .width, unitType: units),
          y: y.calculatedLength(frame: frame, context: context, mode: .height, unitType: units))
      }
    let (red, green, blue, alpha) = shadow.floodColor.sRGBClampedRGBA
    // The flood color is in sRGB, which the filters compute in, and the primitive paints it in its color space.
    func component(_ value: CGFloat) -> Float {
      let c = value / 255
      guard colorSpace == .linearRGB else { return Float(c) }
      return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
    }
    return Self.shadowSteps(
      of: input, offset: offset, deviation: deviation,
      color: [component(red), component(green), component(blue), Float(alpha / 255 * shadow.floodOpacity)],
      region: region, subregion: subregion, result: shadow.result, colorSpace: colorSpace)
  }

  /// The filter region.
  ///
  /// The painting limits a huge region, such as 100000 by 100000, to what shows, so the region is as the attributes
  /// give it here.
  private func effectRect(of filter: SVGFilterElement, frame: CGRect, context: ResolveContext) -> CGRect {
    let units = filter.filterUnits ?? .objectBoundingBox
    let x =
      filter.x?.calculatedLength(frame: frame, context: context, mode: .width, unitType: units, isPosition: true)
      ?? (frame.minX - 0.1 * frame.width)
    let y =
      filter.y?.calculatedLength(frame: frame, context: context, mode: .height, unitType: units, isPosition: true)
      ?? (frame.minY - 0.1 * frame.height)
    let width =
      filter.width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: units)
      ?? 1.2 * frame.width
    let height =
      filter.height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: units)
      ?? 1.2 * frame.height
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// The primitive subregion, whose attributes that the primitive doesn't have come from `defaultSubregion`.
  private func subregion(
    of primitive: any SVGFilterPrimitiveElement, filter: SVGFilterElement, frame: CGRect, context: ResolveContext,
    defaultSubregion: CGRect
  ) -> CGRect {
    let primitiveUnits = filter.primitiveUnits ?? .userSpaceOnUse
    let x =
      primitive.x?.calculatedLength(
        frame: frame, context: context, mode: .width, unitType: primitiveUnits, isPosition: true)
      ?? defaultSubregion.minX
    let y =
      primitive.y?.calculatedLength(
        frame: frame, context: context, mode: .height, unitType: primitiveUnits, isPosition: true)
      ?? defaultSubregion.minY
    let width =
      primitive.width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: primitiveUnits)
      ?? defaultSubregion.width
    let height =
      primitive.height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: primitiveUnits)
      ?? defaultSubregion.height
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// The inputs of a primitive, where `nil` is the result of the primitive before. A `feTile` has none here, because
  /// its subregion defaults to the filter region whatever its input is.
  private static func inputs(of primitive: any SVGFilterPrimitiveElement) -> [SVGFilterInput?] {
    switch primitive {
    case let blend as SVGFeBlendElement: [blend.input, blend.input2]
    case let colorMatrix as SVGFeColorMatrixElement: [colorMatrix.input]
    case let transfer as SVGFeComponentTransferElement: [transfer.input]
    case let composite as SVGFeCompositeElement: [composite.input, composite.input2]
    case let displacement as SVGFeDisplacementMapElement: [displacement.input, displacement.input2]
    case let convolve as SVGFeConvolveMatrixElement: [convolve.input]
    case let diffuse as SVGFeDiffuseLightingElement: [diffuse.input]
    case let specular as SVGFeSpecularLightingElement: [specular.input]
    case let shadow as SVGFeDropShadowElement: [shadow.input]
    case let blur as SVGFeGaussianBlurElement: [blur.input]
    case let merge as SVGFeMergeElement: merge.children.compactMap { $0 as? SVGFeMergeNodeElement }.map(\.input)
    case let morphology as SVGFeMorphologyElement: [morphology.input]
    case let offset as SVGFeOffsetElement: [offset.input]
    default: []
    }
  }

  private func primitive(
    of element: any SVGFilterPrimitiveElement, filter: SVGFilterElement, frame: CGRect, context: ResolveContext
  ) -> FilterPrimitive {
    switch element {
    case let blend as SVGFeBlendElement:
      return .blend(mode: (blend.mode ?? .normal).toCgBlendMode, input: blend.input, input2: blend.input2)
    case let colorMatrix as SVGFeColorMatrixElement:
      return .colorMatrix(input: colorMatrix.input, matrix: Self.matrix(of: colorMatrix))
    case let transfer as SVGFeComponentTransferElement:
      // The last function of a component is the one that the primitive uses.
      var functions = [SVGElementName: TransferFunction]()
      for case let function as SVGFeFuncElement in transfer.children {
        functions[function.type] = Self.transferFunction(of: function)
      }
      return .componentTransfer(
        input: transfer.input, red: functions[.feFuncR] ?? .identity, green: functions[.feFuncG] ?? .identity,
        blue: functions[.feFuncB] ?? .identity, alpha: functions[.feFuncA] ?? .identity)
    case let composite as SVGFeCompositeElement:
      return .composite(
        operator: composite.compositeOperator,
        k: [composite.k1, composite.k2, composite.k3, composite.k4].map(Float.init), input: composite.input,
        input2: composite.input2)
    case let morphology as SVGFeMorphologyElement:
      var radius = morphology.radius
      if filter.primitiveUnits == .objectBoundingBox {
        radius = CGSize(width: radius.width * frame.width, height: radius.height * frame.height)
      }
      return .morphology(input: morphology.input, operator: morphology.morphologyOperator, radius: radius)
    case let convolve as SVGFeConvolveMatrixElement:
      return .convolveMatrix(input: convolve.input, Self.convolveMatrix(of: convolve))
    case let diffuse as SVGFeDiffuseLightingElement:
      let reflection: LightingPrimitive.Reflection? =
        diffuse.diffuseConstant >= 0 ? .diffuse(constant: Float(diffuse.diffuseConstant)) : nil
      return .lighting(
        input: diffuse.input,
        Self.lighting(
          reflection, surfaceScale: diffuse.surfaceScale, color: diffuse.lightingColor,
          lightSource: diffuse.lightSource, filter: filter, frame: frame, context: context))
    case let specular as SVGFeSpecularLightingElement:
      let reflection: LightingPrimitive.Reflection? =
        specular.specularConstant >= 0
        ? .specular(constant: Float(specular.specularConstant), exponent: Float(specular.specularExponent)) : nil
      return .lighting(
        input: specular.input,
        Self.lighting(
          reflection, surfaceScale: specular.surfaceScale, color: specular.lightingColor,
          lightSource: specular.lightSource, filter: filter, frame: frame, context: context))
    case let displacement as SVGFeDisplacementMapElement:
      var scale = CGSize(width: displacement.scale, height: displacement.scale)
      if filter.primitiveUnits == .objectBoundingBox {
        scale = CGSize(width: scale.width * frame.width, height: scale.height * frame.height)
      }
      return .displacementMap(
        input: displacement.input, input2: displacement.input2, scale: scale, x: displacement.xChannelSelector,
        y: displacement.yChannelSelector)
    case let flood as SVGFeFloodElement:
      return .flood(color: floodColor(of: flood))
    case let blur as SVGFeGaussianBlurElement:
      let units = filter.primitiveUnits ?? .userSpaceOnUse
      let standardDeviation: GaussianBlurPrimitive.StandardDeviation =
        switch blur.stdDeviation ?? .zero {
        case .iso(let value):
          .iso(value.calculatedLength(frame: frame, context: context, mode: .other, unitType: units))
        case .hetero(let x, let y):
          .hetero(
            x: x.calculatedLength(frame: frame, context: context, mode: .width, unitType: units),
            y: y.calculatedLength(frame: frame, context: context, mode: .height, unitType: units))
        }
      return .gaussianBlur(
        GaussianBlurPrimitive(input: blur.input, standardDeviation: standardDeviation))
    case let merge as SVGFeMergeElement:
      return .merge(inputs: merge.children.compactMap { $0 as? SVGFeMergeNodeElement }.map(\.input))
    case let offset as SVGFeOffsetElement:
      let dx = offset.dx ?? 0
      let dy = offset.dy ?? 0
      return switch filter.primitiveUnits ?? .userSpaceOnUse {
      case .userSpaceOnUse:
        .offset(input: offset.input, translation: CGAffineTransform(translationX: dx, y: dy))
      case .objectBoundingBox:
        .offset(input: offset.input, translation: CGAffineTransform(translationX: dx * frame.width, y: dy * frame.height))
      }
    case let turbulence as SVGFeTurbulenceElement:
      // The base frequencies aren't lengths, so the units of the bounding box don't change them.
      return .turbulence(
        TurbulencePrimitive(
          type: turbulence.turbulenceType, baseFrequency: turbulence.baseFrequency,
          numOctaves: turbulence.numOctaves, seed: turbulence.seed, stitchTiles: turbulence.stitchTiles))
    default:
      preconditionFailure("\(element.type.rawValue) isn't a filter primitive")
    }
  }

  /// The light of a lighting primitive, or `nil` for a reflection in error or a missing light source, which give
  /// transparent black.
  ///
  /// Wide colors of `lighting-color` are clamped to sRGB, which the filters compute in. The positions of the light
  /// sources are in the units of the primitives, where `z` of the units of the bounding box is a fraction of its
  /// diagonal divided by the square root of 2.
  static func lighting(
    _ reflection: LightingPrimitive.Reflection?, surfaceScale: Double, color: SVGColor,
    lightSource: (any SVGLightSourceElement)?, filter: SVGFilterElement, frame: CGRect, context: ResolveContext
  ) -> LightingPrimitive? {
    guard let reflection, let lightSource else { return nil }
    let units = filter.primitiveUnits ?? .userSpaceOnUse
    func position(_ x: SVGLength, _ y: SVGLength, _ z: SVGLength) -> SIMD3<Float> {
      var depth = z.value(context: context, mode: .other, unitType: units)
      if units == .objectBoundingBox {
        depth *= sqrt(frame.width * frame.width + frame.height * frame.height) / sqrt(2)
      }
      return SIMD3(
        Float(x.calculatedLength(frame: frame, context: context, mode: .width, unitType: units, isPosition: true)),
        Float(y.calculatedLength(frame: frame, context: context, mode: .height, unitType: units, isPosition: true)),
        Float(depth))
    }
    let light: LightingPrimitive.LightSource
    switch lightSource {
    case let distant as SVGFeDistantLightElement:
      light = .distant(azimuth: Float(distant.azimuth), elevation: Float(distant.elevation))
    case let point as SVGFePointLightElement:
      light = .point(position: position(point.x, point.y, point.z))
    case let spot as SVGFeSpotLightElement:
      light = .spot(
        position: position(spot.x, spot.y, spot.z),
        pointsAt: position(spot.pointsAtX, spot.pointsAtY, spot.pointsAtZ),
        specularExponent: Float(spot.specularExponent), limitingConeAngle: spot.limitingConeAngle.map(Float.init))
    default:
      return nil
    }
    let (red, green, blue, _) = color.sRGBClampedRGBA
    return LightingPrimitive(
      reflection: reflection, surfaceScale: Float(surfaceScale),
      color: SIMD3(Float(red / 255), Float(green / 255), Float(blue / 255)), lightSource: light)
  }

  /// The kernel of a `feConvolveMatrix`, or `nil` for a target out of the kernel, which the specification doesn't
  /// allow and which gives transparent black.
  ///
  /// An order that isn't positive, or a kernel that doesn't have as many numbers as the order, makes the primitive
  /// pass its input through. A divisor that is missing or 0 is the sum of the kernel, or 1 if the sum is 0 within the rounding of its numbers.
  static func convolveMatrix(of element: SVGFeConvolveMatrixElement) -> ConvolveMatrixPrimitive? {
    let (columns, rows) = element.order
    guard columns > 0, rows > 0, element.kernelMatrix.count == columns * rows else { return .passThrough }
    let targetX = element.targetX ?? columns / 2
    let targetY = element.targetY ?? rows / 2
    guard (0..<columns).contains(targetX), (0..<rows).contains(targetY) else { return nil }
    var divisor = element.divisor ?? 0
    if divisor == 0 {
      // A sum of numbers that aren't exact in binary, such as 0.1 eight times and -0.8, is 0 within their rounding.
      let sum = element.kernelMatrix.reduce(0, +)
      let magnitude = element.kernelMatrix.reduce(0) { $0 + abs($1) }
      divisor = abs(sum) <= magnitude * 1e-9 ? 1 : sum
    }
    return ConvolveMatrixPrimitive(
      columns: columns, rows: rows, kernel: element.kernelMatrix.map(Float.init), divisor: Float(divisor),
      bias: Float(element.bias), targetX: targetX,
      targetY: targetY, edgeMode: element.edgeMode, preserveAlpha: element.preserveAlpha)
  }

  /// The matrix of a `feColorMatrix`, as the specification makes it from its `type` and `values`. Values that aren't
  /// one number, or 20 for `matrix`, are missing, and a missing value gives the matrix that changes nothing.
  static func matrix(of element: SVGFeColorMatrixElement) -> [Float] {
    let identity: [Double] = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ]
    let values = element.values
    let single = values?.count == 1 ? values?.first : nil
    let matrix: [Double]
    switch element.matrixType {
    case .matrix:
      matrix = values?.count == 20 ? values! : identity
    case .saturate:
      matrix = saturateMatrix(single ?? 1)
    case .hueRotate:
      matrix = hueRotateMatrix(degrees: single ?? 0)
    case .luminanceToAlpha:
      matrix = [
        0, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
        0.2125, 0.7154, 0.0721, 0, 0,
      ]
    }
    return matrix.map(Float.init)
  }

  /// The matrix of `saturate`, which leaves the colors as they are at 1, and makes them gray at 0.
  static func saturateMatrix(_ s: Double) -> [Double] {
    [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
      0, 0, 0, 1, 0,
    ]
  }

  /// The matrix of `hueRotate`, which rotates the hues by an angle in degrees.
  static func hueRotateMatrix(degrees: Double) -> [Double] {
    let angle = degrees * .pi / 180
    let c = cos(angle)
    let s = sin(angle)
    return [
      0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
      0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
      0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
      0, 0, 0, 1, 0,
    ]
  }

  /// The transfer function of a `feFuncR`, `feFuncG`, `feFuncB` or `feFuncA`. A missing or invalid `type`, and a
  /// table without values, change nothing, and a missing or invalid number has its initial value.
  static func transferFunction(of element: SVGFeFuncElement) -> TransferFunction {
    let values = (element.tableValues ?? []).map(Float.init)
    switch element.functionType ?? .identity {
    case .identity:
      return .identity
    case .table:
      return values.isEmpty ? .identity : .table(values)
    case .discrete:
      return values.isEmpty ? .identity : .discrete(values)
    case .linear:
      return .linear(slope: Float(element.slope ?? 1), intercept: Float(element.intercept ?? 0))
    case .gamma:
      return .gamma(
        amplitude: Float(element.amplitude ?? 1), exponent: Float(element.exponent ?? 1),
        offset: Float(element.offset ?? 0))
    }
  }

  /// The color of a flood, premultiplied by its alpha and the flood opacity, in the order of the pixels of the
  /// bitmap, which is in sRGB, so a color outside it is clamped to it.
  private func floodColor(of flood: SVGFeFloodElement) -> [UInt8] {
    let (red:r, green:g, blue:b, alpha:a) = flood.floodColor.sRGBClampedRGBA
    let opacity = flood.floodOpacity
    let alpha = opacity * a / 255
    let y = (r * 0.2125 + g * 0.7154 + b * 0.0721) * alpha
    let u = (r * -0.115 + g * -0.386 + b * 0.5) * alpha
    let v = (r * 0.5 + g * -0.454 + b * -0.046) * alpha
    // The conversion through luma and chroma can make a component of 0 a little less than 0.
    func component(_ value: CGFloat) -> UInt8 { UInt8(min(max(round(value), 0), 255)) }
    return [
      component(y + u * 1.8558),
      component(y + u * -0.187 + v * -0.4678),
      component(y + v * 1.575),
      UInt8((a * opacity).rounded(.toNearestOrAwayFromZero)),
    ]
  }
}
