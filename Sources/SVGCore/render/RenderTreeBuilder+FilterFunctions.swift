import CoreGraphics
import Foundation

extension RenderTreeBuilder {
  /// What a filter function of the CSS does to its source, as the primitives that the specification makes it equal
  /// to, or `nil` if the source paints nothing.
  ///
  /// The functions compute in sRGB, whatever `color-interpolation-filters` is. They have no filter region: the
  /// effect covers what the source paints, and as far as a blur and the offset of a shadow move it.
  func functionEffect(
    of function: SVGFilterFunction, element: any SVGDrawableElement, source: RenderNode?, frame: CGRect,
    context: ResolveContext
  ) -> FilterEffect? {
    guard let bounds = source?.paintedBounds, !bounds.isNull, !bounds.isEmpty else { return nil }
    // What the source paints at its antialiased edges.
    let painted = bounds.insetBy(dx: -1 / scale, dy: -1 / scale)
    func length(_ length: SVGLength, _ mode: SVGLengthMode) -> CGFloat {
      length.calculatedLength(frame: frame, context: context, mode: mode)
    }
    let effectRect: CGRect
    let primitives: [FilterPrimitive]
    switch function {
    case .url:
      return nil
    case .blur(let deviation):
      let deviation = max(length(deviation, .other), 0)
      effectRect = painted.insetBy(dx: -3 * deviation, dy: -3 * deviation)
      primitives = [.gaussianBlur(GaussianBlurPrimitive(input: nil, standardDeviation: .iso(deviation)))]
    case .dropShadow(let color, let dx, let dy, let deviation):
      let offset = CGSize(width: length(dx, .width), height: length(dy, .height))
      let deviation = max(length(deviation, .other), 0)
      let shadow = painted.offsetBy(dx: offset.width, dy: offset.height).insetBy(dx: -3 * deviation, dy: -3 * deviation)
      effectRect = painted.union(shadow)
      let svgColor: SVGColor =
        switch color {
        case .color(let color): color
        case .currentColor: element.style.color
        case .expression(let expression): expression.resolved(currentColor: element.style.color)
        }
      // The shadow is computed in sRGB, so a color outside it is clamped to it.
      let (red, green, blue, alpha) = svgColor.sRGBClampedRGBA
      return FilterEffect(
        effectRect: effectRect, colorInterpolation: .sRGB, colorInterpolationFilters: .sRGB,
        primitives: Self.shadowSteps(
          of: .sourceGraphic, offset: offset, deviation: .iso(deviation),
          color: [Float(red / 255), Float(green / 255), Float(blue / 255), Float(alpha / 255)], region: effectRect,
          subregion: effectRect, result: nil, colorSpace: .sRGB))
    case .colorAdjust(let adjust, let amount):
      effectRect = painted
      primitives = [Self.primitive(of: adjust, amount: amount)]
    case .hueRotate(let degrees):
      effectRect = painted
      primitives = [.colorMatrix(input: nil, matrix: Self.hueRotateMatrix(degrees: degrees).map(Float.init))]
    }
    return FilterEffect(
      effectRect: effectRect, colorInterpolation: .sRGB, colorInterpolationFilters: .sRGB,
      primitives: primitives.map {
        FilterStep(primitive: $0, subregion: effectRect, result: nil, colorSpace: .sRGB)
      })
  }

  /// The steps of a shadow under an input, as `feDropShadow` and `drop-shadow()` make it: the alpha of the input,
  /// colored by a color, blurred, moved by an offset, and the input over it.
  ///
  /// The color is uniform, so coloring the alpha before the blur paints what the specification paints with a flood
  /// that the blurred alpha masks. The result is clipped to the subregion, and the steps before it only to the region
  /// of the filter, so that the shadow is clipped after it's moved.
  ///
  /// - Parameter color: The red, green, blue and alpha of the color, from 0 to 1 in the color space, without the alpha
  ///   premultiplied.
  static func shadowSteps(
    of input: SVGFilterInput, offset: CGSize, deviation: GaussianBlurPrimitive.StandardDeviation, color: [Float],
    region: CGRect, subregion: CGRect, result: String?, colorSpace: SVGColorInterpolation
  ) -> [FilterStep] {
    let primitives: [FilterPrimitive] = [
      .colorMatrix(
        input: input,
        matrix: [
          0, 0, 0, 0, color[0],
          0, 0, 0, 0, color[1],
          0, 0, 0, 0, color[2],
          0, 0, 0, color[3], 0,
        ]),
      .gaussianBlur(GaussianBlurPrimitive(input: nil, standardDeviation: deviation)),
      .offset(input: nil, translation: CGAffineTransform(translationX: offset.width, y: offset.height)),
    ]
    return primitives.map { FilterStep(primitive: $0, subregion: region, result: nil, colorSpace: colorSpace) }
      + [FilterStep(primitive: .merge(inputs: [nil, input]), subregion: subregion, result: result, colorSpace: colorSpace)]
  }

  /// The primitive that a color adjustment is equal to, as the specification makes it.
  static func primitive(of adjust: SVGColorAdjust, amount a: Double) -> FilterPrimitive {
    func transfer(_ function: TransferFunction, alpha: TransferFunction = .identity) -> FilterPrimitive {
      .componentTransfer(input: nil, red: function, green: function, blue: function, alpha: alpha)
    }
    func matrix(_ values: [Double]) -> FilterPrimitive {
      .colorMatrix(input: nil, matrix: values.map(Float.init))
    }
    let b = 1 - a
    switch adjust {
    case .brightness:
      return transfer(.linear(slope: Float(a), intercept: 0))
    case .contrast:
      return transfer(.linear(slope: Float(a), intercept: Float(0.5 - 0.5 * a)))
    case .invert:
      return transfer(.table([Float(a), Float(b)]))
    case .opacity:
      return transfer(.identity, alpha: .table([0, Float(a)]))
    case .grayscale:
      return matrix([
        0.2126 + 0.7874 * b, 0.7152 - 0.7152 * b, 0.0722 - 0.0722 * b, 0, 0,
        0.2126 - 0.2126 * b, 0.7152 + 0.2848 * b, 0.0722 - 0.0722 * b, 0, 0,
        0.2126 - 0.2126 * b, 0.7152 - 0.7152 * b, 0.0722 + 0.9278 * b, 0, 0,
        0, 0, 0, 1, 0,
      ])
    case .sepia:
      return matrix([
        0.393 + 0.607 * b, 0.769 - 0.769 * b, 0.189 - 0.189 * b, 0, 0,
        0.349 - 0.349 * b, 0.686 + 0.314 * b, 0.168 - 0.168 * b, 0, 0,
        0.272 - 0.272 * b, 0.534 - 0.534 * b, 0.131 + 0.869 * b, 0, 0,
        0, 0, 0, 1, 0,
      ])
    case .saturate:
      return matrix(saturateMatrix(a))
    }
  }
}
