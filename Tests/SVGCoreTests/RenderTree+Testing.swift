import CoreGraphics

@testable import SVGCore

// The values of the cases of the render tree, or `nil` for other cases, which tests pass to `#require`.

extension RenderNode {
  var shape: ShapeNode? { if case .shape(let shape) = self { shape } else { nil } }
  var group: GroupNode? { if case .group(let group) = self { group } else { nil } }
  var viewport: ViewportNode? { if case .viewport(let viewport) = self { viewport } else { nil } }
  var use: UseNode? { if case .use(let use) = self { use } else { nil } }
  var filtered: FilteredNode? { if case .filtered(let filtered) = self { filtered } else { nil } }
}

extension ShapeContent {
  var vector: (fill: FillPaint?, stroke: StrokeStyle?, fillRule: CGPathDrawingMode)? {
    if case .vector(let fill, let stroke, let fillRule) = self { (fill, stroke, fillRule) } else { nil }
  }

  var image: (paint: ImagePaint?, stroke: StrokeStyle?)? {
    if case .image(let paint, let stroke) = self { (paint, stroke) } else { nil }
  }
}

extension FillPaint {
  var color: CGColor? { if case .color(let color) = self { color } else { nil } }
  /// The gradient, which is `nil` itself for a gradient that paints nothing.
  var gradient: GradientPaint?? { if case .gradient(let gradient) = self { gradient } else { nil } }
  /// The pattern, which is `nil` itself for a pattern that paints nothing.
  var pattern: PatternPaint?? { if case .pattern(let pattern) = self { pattern } else { nil } }
}

extension GradientPaint {
  var linear: LinearGradientPaint? { if case .linear(let gradient) = self { gradient } else { nil } }
  var radial: RadialGradientPaint? { if case .radial(let gradient) = self { gradient } else { nil } }
}

extension MaskApplication {
  var mask: MaskEffect? { if case .mask(let mask) = self { mask } else { nil } }
}

extension ImageContent {
  var document: RenderNode? { if case .document(let node) = self { node } else { nil } }
}

extension ImagePrimitive {
  var picture: ImagePaint? { if case .picture(let paint) = self { paint } else { nil } }
  var element: (node: RenderNode, origin: CGPoint)? {
    if case .element(let node, let origin) = self { (node, origin) } else { nil }
  }
}

extension FilterPrimitive {
  var colorMatrix: (input: SVGFilterInput?, matrix: [Float])? {
    if case .colorMatrix(let input, let matrix) = self { (input, matrix) } else { nil }
  }
  var image: ImagePrimitive?? { if case .image(let image) = self { image } else { nil } }
  var lighting: (input: SVGFilterInput?, lighting: LightingPrimitive?)? {
    if case .lighting(let input, let lighting) = self { (input, lighting) } else { nil }
  }
  var morphology: (input: SVGFilterInput?, operator: SVGMorphologyOperator, radius: CGSize)? {
    if case .morphology(let input, let morphologyOperator, let radius) = self {
      (input, morphologyOperator, radius)
    } else {
      nil
    }
  }
  var displacementMap: (input: SVGFilterInput?, input2: SVGFilterInput?, scale: CGSize, x: SVGChannelSelector, y: SVGChannelSelector)? {
    if case .displacementMap(let input, let input2, let scale, let x, let y) = self {
      (input, input2, scale, x, y)
    } else {
      nil
    }
  }
  var gaussianBlur: GaussianBlurPrimitive? { if case .gaussianBlur(let blur) = self { blur } else { nil } }
  var merge: [SVGFilterInput?]? { if case .merge(let inputs) = self { inputs } else { nil } }
  var offset: (input: SVGFilterInput?, translation: CGAffineTransform)? {
    if case .offset(let input, let translation) = self { (input, translation) } else { nil }
  }
  var turbulence: TurbulencePrimitive?? { if case .turbulence(let turbulence) = self { turbulence } else { nil } }
}
