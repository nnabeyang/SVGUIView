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
    // A reference to something that isn't a filter element makes the element have no filters.
    var filters = [String: SVGFilterElement]()
    for case .url(let id) in functions {
      guard let filter = base.filters[id] else { return .none }
      // A filter element without children draws nothing, which nothing after it can draw from.
      guard !filter.knownChildren.isEmpty else { return .filtered(nil) }
      filters[id] = filter
    }
    let elementContext = context.styled(by: element)
    let path = await path(of: element, context: elementContext, guard: references)
    let frame = await frame(of: element, context: elementContext, path: path, guard: references)
    // The filter draws the element in a context of its own, with the viewBox and nothing else of the context.
    let sourceContext = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: context.viewBox)
    var source = await nodeWithoutFilter(
      of: element, context: sourceContext, mode: .filter(isRoot: true), guard: ReferenceGuard(), instance: instance)
    let id = RenderID(element: element.base.elementID, instance: instance)
    // The last filter draws the result with the transform, the opacity and the blending of the element, and the
    // others draw theirs into the source of the next one as they are.
    let transform = await transform(of: element, context: elementContext, frame: frame, guard: references)
    for (i, function) in functions.enumerated() {
      let isLast = i == functions.count - 1
      let effect: FilterEffect?
      if case .url(let filterID) = function, let filter = filters[filterID] {
        let region = effectRect(of: filter, frame: frame, context: context)
        effect = FilterEffect(
          effectRect: region, colorInterpolation: filter.colorInterpolation ?? .sRGB,
          colorInterpolationFilters: filter.colorInterpolationFilters ?? .linearRGB,
          primitives: primitives(of: filter, region: region, frame: frame, context: context))
      } else {
        effect = functionEffect(of: function, element: element, source: source, frame: frame, context: elementContext)
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
          blendMode: isLast ? element.style.mixBlendMode.cgBlendMode : .normal))
    }
    return .filtered(source)
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
  private func primitives(
    of filter: SVGFilterElement, region: CGRect, frame: CGRect, context: ResolveContext
  ) -> [FilterStep] {
    var steps = [FilterStep]()
    for child in filter.knownChildren {
      guard let child = child as? (any SVGFilterPrimitiveElement) else { continue }
      let subregion = subregion(of: child, filter: filter, frame: frame, context: context)
      // The property is inherited, so the primitive has the value of the filter element where it declares none, and
      // the initial value is linearRGB.
      let colorSpace = child.base.style.colorInterpolationFilters ?? .linearRGB
      if let shadow = child as? SVGFeDropShadowElement {
        let input = shadow.input ?? previousResult(of: &steps)
        steps += dropShadowSteps(
          of: shadow, input: input, filter: filter, region: region, subregion: subregion, frame: frame,
          context: context, colorSpace: colorSpace)
        continue
      }
      steps.append(
        FilterStep(
          primitive: primitive(of: child, filter: filter, frame: frame, context: context), subregion: subregion,
          result: child.result, colorSpace: colorSpace))
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
    let (red, green, blue, alpha) = shadow.floodColor.rgba
    // The flood color is in sRGB, and the primitive paints it in its color space.
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

  /// The primitive subregion, whose attributes that the primitive doesn't have come from the filter region.
  private func subregion(
    of primitive: any SVGFilterPrimitiveElement, filter: SVGFilterElement, frame: CGRect, context: ResolveContext
  ) -> CGRect {
    let primitiveUnits = filter.primitiveUnits ?? .userSpaceOnUse
    let filterUnits = filter.filterUnits ?? .objectBoundingBox
    let x =
      primitive.x?.calculatedLength(
        frame: frame, context: context, mode: .width, unitType: primitiveUnits, isPosition: true)
      ?? filter.x?.calculatedLength(
        frame: frame, context: context, mode: .width, unitType: filterUnits, isPosition: true)
      ?? (frame.minX - 0.1 * frame.width)
    let y =
      primitive.y?.calculatedLength(
        frame: frame, context: context, mode: .height, unitType: primitiveUnits, isPosition: true)
      ?? filter.y?.calculatedLength(
        frame: frame, context: context, mode: .height, unitType: filterUnits, isPosition: true)
      ?? (frame.minY - 0.1 * frame.height)
    let width =
      primitive.width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: primitiveUnits)
      ?? filter.width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits)
      ?? 1.2 * frame.width
    let height =
      primitive.height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: primitiveUnits)
      ?? filter.height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits)
      ?? 1.2 * frame.height
    return CGRect(x: x, y: y, width: width, height: height)
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
    default:
      preconditionFailure("\(element.type.rawValue) isn't a filter primitive")
    }
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
  /// bitmap.
  private func floodColor(of flood: SVGFeFloodElement) -> [UInt8] {
    let (red:r, green:g, blue:b, alpha:a) = flood.floodColor.rgba
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
