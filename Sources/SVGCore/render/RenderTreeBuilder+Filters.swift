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

  /// Applies the filter of an element, if it has one.
  ///
  /// - Parameters:
  ///   - context: The context of the parent of the element.
  ///   - references: The guard that the bounds of the element are found with.
  func filtering(
    of element: any SVGDrawableElement, context: ResolveContext, guard references: ReferenceGuard,
    instance: [ElementID]
  ) async -> Filtering {
    guard case .url(let id) = element.filter ?? .none, let filter = base.filters[id] else { return .none }
    guard !filter.knownChildren.isEmpty else { return .filtered(nil) }
    let elementContext = context.styled(by: element)
    let path = await path(of: element, context: elementContext, guard: references)
    let frame = await frame(of: element, context: elementContext, path: path, guard: references)
    var primitives = [FilterStep]()
    for (i, child) in filter.knownChildren.enumerated() {
      guard let child = child as? (any SVGFilterPrimitiveElement) else { continue }
      primitives.append(
        FilterStep(
          primitive: primitive(of: child, filter: filter, frame: frame, context: context),
          subregion: subregion(of: child, filter: filter, frame: frame, context: context), result: child.result,
          isFirst: i == 0))
    }
    // The filter draws the element in a context of its own, with the viewBox and nothing else of the context.
    let sourceContext = ResolveContext(base: base, viewPort: viewPort, scale: scale, viewBox: context.viewBox)
    let source = await nodeWithoutFilter(
      of: element, context: sourceContext, mode: .filter(isRoot: true), guard: ReferenceGuard(), instance: instance)
    return .filtered(
      .filtered(
        FilteredNode(
          id: RenderID(element: element.base.elementID, instance: instance),
          transform: await transform(of: element, context: elementContext, frame: frame, guard: references),
          frame: frame, effectRect: effectRect(of: filter, frame: frame, context: context),
          colorInterpolation: filter.colorInterpolation ?? .sRGB,
          colorInterpolationFilters: filter.colorInterpolationFilters ?? .linearRGB, opacity: element.opacity,
          primitives: primitives, source: source, blendMode: element.style.mixBlendMode.cgBlendMode)))
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
        GaussianBlurPrimitive(
          input: blur.input, standardDeviation: standardDeviation,
          colorInterpolationFilters: blur.colorInterpolationFilters,
          filterColorInterpolationFilters: filter.colorInterpolationFilters))
    case let merge as SVGFeMergeElement:
      return .merge(
        inputs: merge.children.compactMap { $0 as? SVGFeMergeNodeElement }.map(\.input),
        colorInterpolationFilters: merge.colorInterpolationFilters)
    case let offset as SVGFeOffsetElement:
      let dx = offset.dx ?? 0
      let dy = offset.dy ?? 0
      return switch filter.primitiveUnits ?? .userSpaceOnUse {
      case .userSpaceOnUse:
        .offset(translation: CGAffineTransform(translationX: dx, y: dy))
      case .objectBoundingBox:
        .offset(translation: CGAffineTransform(translationX: dx * frame.width, y: dy * frame.height))
      }
    default:
      preconditionFailure("\(element.type.rawValue) isn't a filter primitive")
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
