import CoreGraphics
import Foundation

/// The properties that styles set, by their names in CSS.
///
/// The order of the cases is the order in which computed values are computed: a property's computed value can
/// depend on the computed values of the properties before it, such as `font-size` on `font-family`, and lengths in
/// `em` on `font-size`.
enum PropertyID: String, CaseIterable, Sendable {
  case fontFamily = "font-family"
  case fontSize = "font-size"
  case fontWeight = "font-weight"
  case writingMode = "writing-mode"
  case color
  case fill
  case fillOpacity = "fill-opacity"
  case fillRule = "fill-rule"
  case stroke
  case strokeOpacity = "stroke-opacity"
  case strokeWidth = "stroke-width"
  case strokeLinecap = "stroke-linecap"
  case strokeLinejoin = "stroke-linejoin"
  case strokeMiterlimit = "stroke-miterlimit"
  case strokeDasharray = "stroke-dasharray"
  case strokeDashoffset = "stroke-dashoffset"
  case paintOrder = "paint-order"
  case clipRule = "clip-rule"
  case textAnchor = "text-anchor"
  case whiteSpace = "white-space"
  case textDecoration = "text-decoration"
  case letterSpacing = "letter-spacing"
  case wordSpacing = "word-spacing"
  case dominantBaseline = "dominant-baseline"
  case alignmentBaseline = "alignment-baseline"
  case baselineShift = "baseline-shift"
  case markerStart = "marker-start"
  case markerMid = "marker-mid"
  case markerEnd = "marker-end"
  case visibility
  case colorInterpolation = "color-interpolation"
  case colorInterpolationFilters = "color-interpolation-filters"
  case opacity
  case transform
  case transformOrigin = "transform-origin"
  case transformBox = "transform-box"
  case clipPath = "clip-path"
  case mask
  case filter
  case display
  case overflow
  case stopColor = "stop-color"
  case stopOpacity = "stop-opacity"
  case floodColor = "flood-color"
  case floodOpacity = "flood-opacity"
  case x
  case y
  case width
  case height
  case d
  case animationName = "animation-name"
  case animationDuration = "animation-duration"
  case animationTimingFunction = "animation-timing-function"
  case animationDelay = "animation-delay"
  case animationIterationCount = "animation-iteration-count"
  case animationDirection = "animation-direction"
  case animationFillMode = "animation-fill-mode"
  case animationPlayState = "animation-play-state"
  case transitionProperty = "transition-property"
  case transitionDuration = "transition-duration"
  case transitionTimingFunction = "transition-timing-function"
  case transitionDelay = "transition-delay"
  case transitionBehavior = "transition-behavior"

  /// The description of the property.
  var property: any StyleProperty.Type {
    var visitor = PropertyTypeVisitor()
    return visit(&visitor)
  }

  /// Calls the visitor with the type that describes the property, so that what the visitor does is specialized for
  /// the property instead of going through ``property``.
  func visit<V: StylePropertyVisitor>(_ visitor: inout V) -> V.Result {
    switch self {
    case .fontFamily: visitor.visit(FontFamilyProperty.self)
    case .fontSize: visitor.visit(FontSizeProperty.self)
    case .fontWeight: visitor.visit(FontWeightProperty.self)
    case .writingMode: visitor.visit(WritingModeProperty.self)
    case .color: visitor.visit(ColorProperty.self)
    case .fill: visitor.visit(FillProperty.self)
    case .fillOpacity: visitor.visit(FillOpacityProperty.self)
    case .fillRule: visitor.visit(FillRuleProperty.self)
    case .stroke: visitor.visit(StrokeProperty.self)
    case .strokeOpacity: visitor.visit(StrokeOpacityProperty.self)
    case .strokeWidth: visitor.visit(StrokeWidthProperty.self)
    case .strokeLinecap: visitor.visit(StrokeLinecapProperty.self)
    case .strokeLinejoin: visitor.visit(StrokeLinejoinProperty.self)
    case .strokeMiterlimit: visitor.visit(StrokeMiterlimitProperty.self)
    case .strokeDasharray: visitor.visit(StrokeDasharrayProperty.self)
    case .strokeDashoffset: visitor.visit(StrokeDashoffsetProperty.self)
    case .paintOrder: visitor.visit(PaintOrderProperty.self)
    case .clipRule: visitor.visit(ClipRuleProperty.self)
    case .textAnchor: visitor.visit(TextAnchorProperty.self)
    case .whiteSpace: visitor.visit(WhiteSpaceProperty.self)
    case .textDecoration: visitor.visit(TextDecorationProperty.self)
    case .letterSpacing: visitor.visit(LetterSpacingProperty.self)
    case .wordSpacing: visitor.visit(WordSpacingProperty.self)
    case .dominantBaseline: visitor.visit(DominantBaselineProperty.self)
    case .alignmentBaseline: visitor.visit(AlignmentBaselineProperty.self)
    case .baselineShift: visitor.visit(BaselineShiftProperty.self)
    case .markerStart: visitor.visit(MarkerStartProperty.self)
    case .markerMid: visitor.visit(MarkerMidProperty.self)
    case .markerEnd: visitor.visit(MarkerEndProperty.self)
    case .visibility: visitor.visit(VisibilityProperty.self)
    case .colorInterpolation: visitor.visit(ColorInterpolationProperty.self)
    case .colorInterpolationFilters: visitor.visit(ColorInterpolationFiltersProperty.self)
    case .opacity: visitor.visit(OpacityProperty.self)
    case .transform: visitor.visit(TransformProperty.self)
    case .transformOrigin: visitor.visit(TransformOriginProperty.self)
    case .transformBox: visitor.visit(TransformBoxProperty.self)
    case .clipPath: visitor.visit(ClipPathProperty.self)
    case .mask: visitor.visit(MaskProperty.self)
    case .filter: visitor.visit(FilterProperty.self)
    case .display: visitor.visit(DisplayProperty.self)
    case .overflow: visitor.visit(OverflowProperty.self)
    case .stopColor: visitor.visit(StopColorProperty.self)
    case .stopOpacity: visitor.visit(StopOpacityProperty.self)
    case .floodColor: visitor.visit(FloodColorProperty.self)
    case .floodOpacity: visitor.visit(FloodOpacityProperty.self)
    case .x: visitor.visit(XProperty.self)
    case .y: visitor.visit(YProperty.self)
    case .width: visitor.visit(WidthProperty.self)
    case .height: visitor.visit(HeightProperty.self)
    case .d: visitor.visit(DProperty.self)
    case .animationName: visitor.visit(AnimationNameProperty.self)
    case .animationDuration: visitor.visit(AnimationDurationProperty.self)
    case .animationTimingFunction: visitor.visit(AnimationTimingFunctionProperty.self)
    case .animationDelay: visitor.visit(AnimationDelayProperty.self)
    case .animationIterationCount: visitor.visit(AnimationIterationCountProperty.self)
    case .animationDirection: visitor.visit(AnimationDirectionProperty.self)
    case .animationFillMode: visitor.visit(AnimationFillModeProperty.self)
    case .animationPlayState: visitor.visit(AnimationPlayStateProperty.self)
    case .transitionProperty: visitor.visit(TransitionPropertyProperty.self)
    case .transitionDuration: visitor.visit(TransitionDurationProperty.self)
    case .transitionTimingFunction: visitor.visit(TransitionTimingFunctionProperty.self)
    case .transitionDelay: visitor.visit(TransitionDelayProperty.self)
    case .transitionBehavior: visitor.visit(TransitionBehaviorProperty.self)
    }
  }
}

private struct PropertyTypeVisitor: StylePropertyVisitor {
  func visit<P: StyleProperty>(_: P.Type) -> any StyleProperty.Type {
    P.self
  }
}

/// The computed values of an element's properties.
///
/// Computed values are a function of the element's cascaded values and its parent's computed values, so that they
/// can be computed again for another parent, such as the `<use>` element that shows the element.
struct ComputedStyle: Sendable, Equatable {
  var fontFamily: String
  var fontSize: SVGUIFont.Size
  var fontWeight: SVGUIFont.Weight
  var writingMode: WritingMode
  var color: SVGColor
  var fill: Paint
  var fillOpacity: Double
  var fillRule: FillRule
  var stroke: Paint
  var strokeOpacity: Double
  var strokeWidth: SVGLength
  var strokeLinecap: CGLineCap
  var strokeLinejoin: CGLineJoin
  var strokeMiterlimit: Double
  var strokeDasharray: [SVGLength]
  var strokeDashoffset: SVGLength
  var paintOrder: PaintOrder
  var clipRule: FillRule
  var textAnchor: TextAnchor
  var whiteSpace: CSSWhiteSpace
  /// The lines of `text-decoration` of the element and its ancestors, which the lines decorate the text of.
  var textDecoration: TextDecorationLines
  /// The space after each character of text, which is 0 for `normal`.
  var letterSpacing: SVGLength
  /// The space added to each space between words, which is 0 for `normal`.
  var wordSpacing: SVGLength
  var dominantBaseline: DominantBaseline
  var alignmentBaseline: AlignmentBaseline
  var baselineShift: BaselineShift
  var markerStart: SVGMarkerReference
  var markerMid: SVGMarkerReference
  var markerEnd: SVGMarkerReference
  var visibility: CSSVisibility
  var colorInterpolation: SVGColorInterpolation?
  var colorInterpolationFilters: SVGColorInterpolation?
  var opacity: Double
  var transform: TransformList
  var transformOrigin: TransformOrigin
  var transformBox: TransformBox
  var clipPath: SVGClipPath
  var mask: SVGMask
  var filter: SVGFilter
  var display: CSSDisplay
  var overflow: SVGOverflow?
  var stopColor: ColorValue
  var stopOpacity: Double
  var floodColor: ColorValue
  var floodOpacity: Double
  var x: SVGLength?
  var y: SVGLength?
  var width: SVGLength?
  var height: SVGLength?
  var d: PathData
  var animationName: [AnimationName]
  var animationDuration: [Double]
  var animationTimingFunction: [EasingFunction]
  var animationDelay: [Double]
  var animationIterationCount: [AnimationIterationCount]
  var animationDirection: [AnimationDirection]
  var animationFillMode: [AnimationFillMode]
  var animationPlayState: [AnimationPlayState]
  var transitionProperty: [TransitionProperty]
  var transitionDuration: [Double]
  var transitionTimingFunction: [EasingFunction]
  var transitionDelay: [Double]
  var transitionBehavior: [TransitionBehavior]
  /// The transform that SMIL `<animateMotion>` elements add after `transform`, which isn't a property.
  var motion = CGAffineTransform.identity

  /// The initial value of every property, which is the style of the parent of the root element.
  static let initial = ComputedStyle(
    fontFamily: FontFamilyProperty.initial, fontSize: FontSizeProperty.initial,
    fontWeight: FontWeightProperty.initial, writingMode: WritingModeProperty.initial, color: ColorProperty.initial,
    fill: FillProperty.initial, fillOpacity: FillOpacityProperty.initial, fillRule: FillRuleProperty.initial,
    stroke: StrokeProperty.initial, strokeOpacity: StrokeOpacityProperty.initial,
    strokeWidth: StrokeWidthProperty.initial, strokeLinecap: StrokeLinecapProperty.initial,
    strokeLinejoin: StrokeLinejoinProperty.initial, strokeMiterlimit: StrokeMiterlimitProperty.initial,
    strokeDasharray: StrokeDasharrayProperty.initial, strokeDashoffset: StrokeDashoffsetProperty.initial,
    paintOrder: PaintOrderProperty.initial,
    clipRule: ClipRuleProperty.initial, textAnchor: TextAnchorProperty.initial,
    whiteSpace: WhiteSpaceProperty.initial, textDecoration: TextDecorationProperty.initial,
    letterSpacing: LetterSpacingProperty.initial, wordSpacing: WordSpacingProperty.initial,
    dominantBaseline: DominantBaselineProperty.initial, alignmentBaseline: AlignmentBaselineProperty.initial,
    baselineShift: BaselineShiftProperty.initial, markerStart: MarkerStartProperty.initial,
    markerMid: MarkerMidProperty.initial, markerEnd: MarkerEndProperty.initial,
    visibility: VisibilityProperty.initial, colorInterpolation: ColorInterpolationProperty.initial,
    colorInterpolationFilters: ColorInterpolationFiltersProperty.initial, opacity: OpacityProperty.initial,
    transform: TransformProperty.initial, transformOrigin: TransformOriginProperty.initial,
    transformBox: TransformBoxProperty.initial, clipPath: ClipPathProperty.initial, mask: MaskProperty.initial,
    filter: FilterProperty.initial, display: DisplayProperty.initial, overflow: OverflowProperty.initial,
    stopColor: StopColorProperty.initial, stopOpacity: StopOpacityProperty.initial,
    floodColor: FloodColorProperty.initial, floodOpacity: FloodOpacityProperty.initial, x: XProperty.initial,
    y: YProperty.initial, width: WidthProperty.initial, height: HeightProperty.initial, d: DProperty.initial,
    animationName: AnimationNameProperty.initial, animationDuration: AnimationDurationProperty.initial,
    animationTimingFunction: AnimationTimingFunctionProperty.initial, animationDelay: AnimationDelayProperty.initial,
    animationIterationCount: AnimationIterationCountProperty.initial,
    animationDirection: AnimationDirectionProperty.initial, animationFillMode: AnimationFillModeProperty.initial,
    animationPlayState: AnimationPlayStateProperty.initial, transitionProperty: TransitionPropertyProperty.initial,
    transitionDuration: TransitionDurationProperty.initial,
    transitionTimingFunction: TransitionTimingFunctionProperty.initial,
    transitionDelay: TransitionDelayProperty.initial, transitionBehavior: TransitionBehaviorProperty.initial)

  /// The computed values of an element with the given cascaded values.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent element, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  ///   - animations: The keyframes of the document and the time of the animations that the element runs, which
  ///     override its values except for important declarations, or `nil` for no animations.
  ///   - smil: The effects of the SMIL animations of the element at the time, in the order that they apply in, which
  ///     CSS animations override.
  ///   - element: The element, whose CSS animations play as the document keeps for them and whose transitions
  ///     override every other value, or `nil` for animations that play from the time that the document was loaded
  ///     and no transitions.
  init(
    cascaded: CascadedValues, parent: ComputedStyle?, root: ComputedStyle?, animations: DocumentAnimations? = nil,
    smil: [SMILEffect] = [], element: ElementID? = nil
  ) {
    var computer = Computer(
      cascaded: cascaded, resolver: StyleResolver(style: .initial, parent: parent ?? .initial, root: root ?? .initial),
      smil: smil.compactMap { effect in effect.property.map { (property: $0, effect: effect) } },
      transitions: element.flatMap { animations?.transitions[$0] } ?? [:], time: animations?.time ?? 0)
    if let animations, !animations.keyframes.isEmpty {
      // The properties of CSS Animations come last in the order, and are computed first to find the animations.
      for id in PropertyID.allCases where id.isAnimation {
        id.visit(&computer)
      }
      computer.animations = ElementAnimation.animations(
        of: computer.resolver.style, element: element, in: animations)
    }
    for id in PropertyID.allCases {
      id.visit(&computer)
    }
    // Motions apply in the order of the sandwich model, each over the ones under it.
    for effect in smil where effect.animation.kind == .animateMotion {
      if let motion = effect.motion(over: computer.resolver.style.motion) {
        computer.resolver.style.motion = motion
      }
    }
    self = computer.resolver.style
  }

  /// Computes the computed values in order, one property at a time, into the style of the resolver, so that
  /// computing a value doesn't copy the styles.
  private struct Computer: StylePropertyVisitor {
    let cascaded: CascadedValues
    var resolver: StyleResolver
    /// The SMIL animations of the element's properties, in the order that they apply in.
    let smil: [(property: PropertyID, effect: SMILEffect)]
    /// The transitions of the element's properties.
    let transitions: [PropertyID: CSSTransition]
    /// The time of the document, in seconds.
    let time: Double
    /// The animations that the element runs, in the order of `animation-name`.
    var animations = [ElementAnimation]()

    mutating func visit<P: StyleProperty>(_: P.Type) {
      var value = resolver.computed(cascaded[P.self], of: P.self)
      // Animations override the cascaded values except for important declarations. SMIL animations come first, and
      // CSS animations override them. A later animation overrides an earlier one, with the value under it as the
      // value that it starts from.
      if P.id.isAnimatable, !cascaded.important.contains(P.id) {
        for (property, effect) in smil where property == P.id {
          if let animated = effect.value(of: P.self, over: value, in: resolver) {
            value = animated
          }
        }
        for animation in animations {
          if let animated = animation.value(of: P.self, over: value, in: resolver) {
            value = animated
          }
        }
      }
      // Transitions override the animations and important declarations.
      if let transition = transitions[P.id], let transitioned = transition.value(of: P.self, at: time, in: resolver) {
        value = transitioned
      }
      resolver.style[keyPath: P.computed] = value
    }
  }

  private init(
    fontFamily: String, fontSize: SVGUIFont.Size, fontWeight: SVGUIFont.Weight, writingMode: WritingMode,
    color: SVGColor, fill: Paint, fillOpacity: Double, fillRule: FillRule, stroke: Paint, strokeOpacity: Double,
    strokeWidth: SVGLength, strokeLinecap: CGLineCap, strokeLinejoin: CGLineJoin, strokeMiterlimit: Double,
    strokeDasharray: [SVGLength], strokeDashoffset: SVGLength, paintOrder: PaintOrder, clipRule: FillRule, textAnchor: TextAnchor,
    whiteSpace: CSSWhiteSpace, textDecoration: TextDecorationLines,
    letterSpacing: SVGLength, wordSpacing: SVGLength, dominantBaseline: DominantBaseline,
    alignmentBaseline: AlignmentBaseline, baselineShift: BaselineShift, markerStart: SVGMarkerReference,
    markerMid: SVGMarkerReference, markerEnd: SVGMarkerReference,
    visibility: CSSVisibility, colorInterpolation: SVGColorInterpolation?,
    colorInterpolationFilters: SVGColorInterpolation?, opacity: Double, transform: TransformList,
    transformOrigin: TransformOrigin, transformBox: TransformBox,
    clipPath: SVGClipPath, mask: SVGMask, filter: SVGFilter, display: CSSDisplay, overflow: SVGOverflow?,
    stopColor: ColorValue, stopOpacity: Double, floodColor: ColorValue, floodOpacity: Double, x: SVGLength?,
    y: SVGLength?, width: SVGLength?, height: SVGLength?, d: PathData, animationName: [AnimationName],
    animationDuration: [Double], animationTimingFunction: [EasingFunction], animationDelay: [Double],
    animationIterationCount: [AnimationIterationCount], animationDirection: [AnimationDirection],
    animationFillMode: [AnimationFillMode], animationPlayState: [AnimationPlayState],
    transitionProperty: [TransitionProperty], transitionDuration: [Double], transitionTimingFunction: [EasingFunction],
    transitionDelay: [Double], transitionBehavior: [TransitionBehavior]
  ) {
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.fontWeight = fontWeight
    self.writingMode = writingMode
    self.color = color
    self.fill = fill
    self.fillOpacity = fillOpacity
    self.fillRule = fillRule
    self.stroke = stroke
    self.strokeOpacity = strokeOpacity
    self.strokeWidth = strokeWidth
    self.strokeLinecap = strokeLinecap
    self.strokeLinejoin = strokeLinejoin
    self.strokeMiterlimit = strokeMiterlimit
    self.strokeDasharray = strokeDasharray
    self.strokeDashoffset = strokeDashoffset
    self.paintOrder = paintOrder
    self.clipRule = clipRule
    self.textAnchor = textAnchor
    self.whiteSpace = whiteSpace
    self.textDecoration = textDecoration
    self.letterSpacing = letterSpacing
    self.wordSpacing = wordSpacing
    self.dominantBaseline = dominantBaseline
    self.alignmentBaseline = alignmentBaseline
    self.baselineShift = baselineShift
    self.markerStart = markerStart
    self.markerMid = markerMid
    self.markerEnd = markerEnd
    self.visibility = visibility
    self.colorInterpolation = colorInterpolation
    self.colorInterpolationFilters = colorInterpolationFilters
    self.opacity = opacity
    self.transform = transform
    self.transformOrigin = transformOrigin
    self.transformBox = transformBox
    self.clipPath = clipPath
    self.mask = mask
    self.filter = filter
    self.display = display
    self.overflow = overflow
    self.stopColor = stopColor
    self.stopOpacity = stopOpacity
    self.floodColor = floodColor
    self.floodOpacity = floodOpacity
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.d = d
    self.animationName = animationName
    self.animationDuration = animationDuration
    self.animationTimingFunction = animationTimingFunction
    self.animationDelay = animationDelay
    self.animationIterationCount = animationIterationCount
    self.animationDirection = animationDirection
    self.animationFillMode = animationFillMode
    self.animationPlayState = animationPlayState
    self.transitionProperty = transitionProperty
    self.transitionDuration = transitionDuration
    self.transitionTimingFunction = transitionTimingFunction
    self.transitionDelay = transitionDelay
    self.transitionBehavior = transitionBehavior
  }

  /// The font, with its size resolved except for viewport units.
  var font: SVGUIFont {
    SVGUIFont(name: fontFamily, size: fontSize, weight: fontWeight)
  }

  /// The paint with `currentColor` resolved.
  func resolved(_ paint: Paint) -> Paint {
    switch paint {
    case .currentColor: .color(color)
    case .url(let id, let fallback?): .url(id, fallback: resolved(fallback))
    default: paint
    }
  }

  /// The color with `currentColor` resolved.
  func resolved(_ value: ColorValue) -> SVGColor {
    switch value {
    case .color(let color): color
    case .currentColor: color
    }
  }
}
