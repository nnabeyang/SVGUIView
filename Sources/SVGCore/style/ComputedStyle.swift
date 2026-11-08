import CoreGraphics
import Foundation
import Synchronization

/// The properties that styles set, by their names in CSS.
///
/// The order of the cases is the order in which computed values are computed: a property's computed value can
/// depend on the computed values of the properties before it, such as `font-size` on `font-family`, and lengths in
/// `em` on `font-size`.
enum PropertyID: String, CaseIterable, Sendable {
  case fontFamily = "font-family"
  case fontSize = "font-size"
  case fontWeight = "font-weight"
  case fontStyle = "font-style"
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
  case shapeRendering = "shape-rendering"
  case imageRendering = "image-rendering"
  case clipRule = "clip-rule"
  case textAnchor = "text-anchor"
  case direction
  case unicodeBidi = "unicode-bidi"
  case textOrientation = "text-orientation"
  case glyphOrientationVertical = "glyph-orientation-vertical"
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
  case mixBlendMode = "mix-blend-mode"
  case isolation
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
  case lightingColor = "lighting-color"
  case x
  case y
  case width
  case height
  case cx
  case cy
  case r
  case rx
  case ry
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
    case .fontStyle: visitor.visit(FontStyleProperty.self)
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
    case .shapeRendering: visitor.visit(ShapeRenderingProperty.self)
    case .imageRendering: visitor.visit(ImageRenderingProperty.self)
    case .clipRule: visitor.visit(ClipRuleProperty.self)
    case .textAnchor: visitor.visit(TextAnchorProperty.self)
    case .direction: visitor.visit(DirectionProperty.self)
    case .unicodeBidi: visitor.visit(UnicodeBidiProperty.self)
    case .textOrientation: visitor.visit(TextOrientationProperty.self)
    case .glyphOrientationVertical: visitor.visit(GlyphOrientationVerticalProperty.self)
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
    case .mixBlendMode: visitor.visit(MixBlendModeProperty.self)
    case .isolation: visitor.visit(IsolationProperty.self)
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
    case .lightingColor: visitor.visit(LightingColorProperty.self)
    case .x: visitor.visit(XProperty.self)
    case .y: visitor.visit(YProperty.self)
    case .width: visitor.visit(WidthProperty.self)
    case .height: visitor.visit(HeightProperty.self)
    case .cx: visitor.visit(CXProperty.self)
    case .cy: visitor.visit(CYProperty.self)
    case .r: visitor.visit(RProperty.self)
    case .rx: visitor.visit(RXProperty.self)
    case .ry: visitor.visit(RYProperty.self)
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
  var fontStyle = FontStyle.normal
  /// The language of the element, from `xml:lang` or `lang` of it or of its nearest ancestor that has one, which
  /// chooses the fonts and the glyphs of text, or `nil` if it's unknown. It isn't a property of CSS.
  var language: Language? = nil
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
  var shapeRendering: ShapeRendering
  var imageRendering = ImageRendering.auto
  var clipRule: FillRule
  var textAnchor: TextAnchor
  var direction = TextDirection.ltr
  var unicodeBidi = UnicodeBidi.normal
  var textOrientation = TextOrientation.mixed
  /// The orientation that `glyph-orientation-vertical` sets, or `nil` for `auto`, which leaves it to
  /// `text-orientation`.
  var glyphOrientationVertical: TextOrientation? = nil
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
  var mixBlendMode: MixBlendMode
  var isolation: Isolation
  var transform: TransformList
  var transformOrigin: TransformOrigin
  var transformBox: TransformBox
  var clipPath: SVGClipPath
  var mask: SVGMask
  var filter: SVGFilter
  var display: CSSDisplay
  var overflow: SVGOverflow
  var stopColor: ColorValue
  var stopOpacity: Double
  var floodColor: ColorValue
  var floodOpacity: Double
  var lightingColor: ColorValue
  var x: SVGLength?
  var y: SVGLength?
  var width: SVGLength?
  var height: SVGLength?
  var cx: SVGLength? = CXProperty.initial
  var cy: SVGLength? = CYProperty.initial
  var r: SVGLength? = RProperty.initial
  var rx: SVGLength? = RXProperty.initial
  var ry: SVGLength? = RYProperty.initial
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
  var motion: CGAffineTransform {
    get { rareValues?.motion ?? .identity }
    set { setRareValues(motion: newValue, customProperties: customProperties) }
  }
  /// The values of the custom properties by their names, with their `var()` substituted, which every element
  /// inherits. A custom property without a value has the guaranteed-invalid value of CSS Variables 1.
  var customProperties: [String: String] {
    get { rareValues?.customProperties ?? [:] }
    set { setRareValues(motion: motion, customProperties: newValue) }
  }
  /// The values that few elements have, apart from the others, or `nil` if the element has none of them. A style is
  /// copied often, and each byte that it holds makes the copies longer, so these values are kept out of it.
  private var rareValues: RareValues?

  /// Values that few elements have, which don't change once they're made.
  private final class RareValues: Sendable, Equatable {
    let motion: CGAffineTransform
    let customProperties: [String: String]

    init(motion: CGAffineTransform, customProperties: [String: String]) {
      self.motion = motion
      self.customProperties = customProperties
    }

    static func == (lhs: RareValues, rhs: RareValues) -> Bool {
      lhs === rhs || (lhs.motion == rhs.motion && lhs.customProperties == rhs.customProperties)
    }
  }

  private mutating func setRareValues(motion: CGAffineTransform, customProperties: [String: String]) {
    rareValues =
      motion == .identity && customProperties.isEmpty
      ? nil : RareValues(motion: motion, customProperties: customProperties)
  }

  /// The initial value of every property, which is the style of the parent of the root element.
  static let initial = ComputedStyle(
    fontFamily: FontFamilyProperty.initial, fontSize: FontSizeProperty.initial,
    fontWeight: FontWeightProperty.initial, writingMode: WritingModeProperty.initial, color: ColorProperty.initial,
    fill: FillProperty.initial, fillOpacity: FillOpacityProperty.initial, fillRule: FillRuleProperty.initial,
    stroke: StrokeProperty.initial, strokeOpacity: StrokeOpacityProperty.initial,
    strokeWidth: StrokeWidthProperty.initial, strokeLinecap: StrokeLinecapProperty.initial,
    strokeLinejoin: StrokeLinejoinProperty.initial, strokeMiterlimit: StrokeMiterlimitProperty.initial,
    strokeDasharray: StrokeDasharrayProperty.initial, strokeDashoffset: StrokeDashoffsetProperty.initial,
    paintOrder: PaintOrderProperty.initial, shapeRendering: ShapeRenderingProperty.initial,
    clipRule: ClipRuleProperty.initial, textAnchor: TextAnchorProperty.initial,
    whiteSpace: WhiteSpaceProperty.initial, textDecoration: TextDecorationProperty.initial,
    letterSpacing: LetterSpacingProperty.initial, wordSpacing: WordSpacingProperty.initial,
    dominantBaseline: DominantBaselineProperty.initial, alignmentBaseline: AlignmentBaselineProperty.initial,
    baselineShift: BaselineShiftProperty.initial, markerStart: MarkerStartProperty.initial,
    markerMid: MarkerMidProperty.initial, markerEnd: MarkerEndProperty.initial,
    visibility: VisibilityProperty.initial, colorInterpolation: ColorInterpolationProperty.initial,
    colorInterpolationFilters: ColorInterpolationFiltersProperty.initial, opacity: OpacityProperty.initial,
    mixBlendMode: MixBlendModeProperty.initial, isolation: IsolationProperty.initial,
    transform: TransformProperty.initial, transformOrigin: TransformOriginProperty.initial,
    transformBox: TransformBoxProperty.initial, clipPath: ClipPathProperty.initial, mask: MaskProperty.initial,
    filter: FilterProperty.initial, display: DisplayProperty.initial, overflow: OverflowProperty.initial,
    stopColor: StopColorProperty.initial, stopOpacity: StopOpacityProperty.initial,
    floodColor: FloodColorProperty.initial, floodOpacity: FloodOpacityProperty.initial,
    lightingColor: LightingColorProperty.initial, x: XProperty.initial,
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
  ///   - computesEveryProperty: Whether the properties that nothing sets are computed as the others are, instead of
  ///     taking the values of the parent or the initial values at once, which tests compare.
  init(
    cascaded: CascadedValues, parent: ComputedStyle?, root: ComputedStyle?, animations: DocumentAnimations? = nil,
    smil: [SMILEffect] = [], element: ElementID? = nil, computesEveryProperty: Bool = false
  ) {
    var computer = Computer(
      cascaded: cascaded, resolver: StyleResolver(style: .initial, parent: parent ?? .initial, root: root ?? .initial),
      smil: smil.compactMap { effect in effect.property.map { (property: $0, effect: effect) } },
      transitions: element.flatMap { animations?.transitions[$0] } ?? [:], time: animations?.time ?? 0)
    // The custom properties come before every other property, whose values they're substituted in. The style starts
    // with none, which most documents have.
    if cascaded.hasVariables {
      computer.resolver.style.customProperties = VariableSubstitution.computedCustomProperties(
        declared: cascaded.customProperties, parent: parent?.customProperties ?? [:])
    } else if let customProperties = parent?.rareValues?.customProperties, !customProperties.isEmpty {
      computer.resolver.style.customProperties = customProperties
    }
    if let animations, !animations.keyframes.isEmpty {
      // The properties of CSS Animations come last in the order, and are computed first to find the animations.
      for id in PropertyID.allCases where id.isAnimation {
        id.visit(&computer)
      }
      computer.animations = ElementAnimation.animations(
        of: computer.resolver.style, element: element, in: animations)
    }
    // Most properties of most elements have no declaration and no animation, and take the values of the parent or
    // the initial values, which the style starts with.
    var isSet = PropertyIndexSet()
    if !computesEveryProperty {
      for id in cascaded.properties { isSet.insert(id) }
      for (id, _) in computer.smil { isSet.insert(id) }
      for id in computer.transitions.keys { isSet.insert(id) }
      // CSS animations change only the properties that their keyframes set, so that an element that animates its
      // transform doesn't compute the other properties again.
      for animation in computer.animations {
        for id in animation.properties { isSet.insert(id) }
      }
    }
    let isInherited = PropertyID.isInheritedByIndex
    for (index, id) in PropertyID.ordered.enumerated() {
      let isUnset = !computesEveryProperty && !isSet.contains(index)
      // A property that nothing sets and that isn't inherited keeps the initial value that the style starts with,
      // so that properties that aren't inherited cost nothing for the elements that don't set them.
      if isUnset, !isInherited[index] { continue }
      computer.isUnset = isUnset
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
    /// Whether nothing sets the property that's visited: no declaration, no animation and no transition.
    var isUnset = false

    mutating func visit<P: StyleProperty>(_: P.Type) {
      if isUnset {
        // The style starts with the initial values.
        if P.isInherited {
          resolver.style[keyPath: P.computed] = resolver.parent[keyPath: P.computed]
        }
        return
      }
      // Most elements have no `var()`, whose values need no substitution.
      let declared =
        cascaded.hasVariables
        ? cascaded.declared(P.self, customProperties: resolver.style.customProperties) : cascaded[P.self]
      var value = resolver.computed(declared, of: P.self)
      // Animations override the cascaded values except for important declarations. SMIL animations come first, and
      // CSS animations override them. A later animation overrides an earlier one, with the value under it as the
      // value that it starts from.
      if P.id.isAnimatable, !smil.isEmpty || !animations.isEmpty, !cascaded.important.contains(P.id) {
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
      if !transitions.isEmpty, let transition = transitions[P.id], let transitioned = transition.value(of: P.self, at: time, in: resolver) {
        value = transitioned
      }
      resolver.style[keyPath: P.computed] = value
    }
  }

  private init(
    fontFamily: String, fontSize: SVGUIFont.Size, fontWeight: SVGUIFont.Weight, writingMode: WritingMode,
    color: SVGColor, fill: Paint, fillOpacity: Double, fillRule: FillRule, stroke: Paint, strokeOpacity: Double,
    strokeWidth: SVGLength, strokeLinecap: CGLineCap, strokeLinejoin: CGLineJoin, strokeMiterlimit: Double,
    strokeDasharray: [SVGLength], strokeDashoffset: SVGLength, paintOrder: PaintOrder,
    shapeRendering: ShapeRendering, clipRule: FillRule, textAnchor: TextAnchor,
    whiteSpace: CSSWhiteSpace, textDecoration: TextDecorationLines,
    letterSpacing: SVGLength, wordSpacing: SVGLength, dominantBaseline: DominantBaseline,
    alignmentBaseline: AlignmentBaseline, baselineShift: BaselineShift, markerStart: SVGMarkerReference,
    markerMid: SVGMarkerReference, markerEnd: SVGMarkerReference,
    visibility: CSSVisibility, colorInterpolation: SVGColorInterpolation?,
    colorInterpolationFilters: SVGColorInterpolation?, opacity: Double, mixBlendMode: MixBlendMode,
    isolation: Isolation, transform: TransformList,
    transformOrigin: TransformOrigin, transformBox: TransformBox,
    clipPath: SVGClipPath, mask: SVGMask, filter: SVGFilter, display: CSSDisplay, overflow: SVGOverflow,
    stopColor: ColorValue, stopOpacity: Double, floodColor: ColorValue, floodOpacity: Double,
    lightingColor: ColorValue, x: SVGLength?,
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
    self.shapeRendering = shapeRendering
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
    self.mixBlendMode = mixBlendMode
    self.isolation = isolation
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
    self.lightingColor = lightingColor
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
    SVGUIFont(name: fontFamily, size: fontSize, weight: fontWeight, style: fontStyle, language: language?.tag)
  }

  /// The paint with `currentColor` resolved.
  func resolved(_ paint: Paint) -> Paint {
    switch paint {
    case .currentColor: .color(color)
    case .expression(let expression): .color(expression.resolved(currentColor: color))
    case .url(let id, let fallback?): .url(id, fallback: resolved(fallback))
    default: paint
    }
  }

  /// The color with `currentColor` resolved.
  func resolved(_ value: ColorValue) -> SVGColor {
    switch value {
    case .color(let color): color
    case .currentColor: color
    case .expression(let expression): expression.resolved(currentColor: color)
    }
  }
}

extension PropertyID {
  /// The properties in the order that their computed values are computed in, which is the order of their cases.
  static let ordered = allCases

  /// Whether each property of ``ordered`` is inherited, by its index.
  static let isInheritedByIndex = ordered.map { $0.property.isInherited }

  /// The index of the property in ``ordered``.
  var index: Int {
    Self.ordered.firstIndex(of: self)!
  }
}

/// A set of properties by their indexes in ``PropertyID/ordered``, which doesn't hash their names.
private struct PropertyIndexSet {
  private var low: UInt64 = 0
  private var high: UInt64 = 0

  mutating func insert(_ id: PropertyID) {
    let index = id.index
    if index < 64 { low |= 1 << index } else { high |= 1 << (index - 64) }
  }

  func contains(_ index: Int) -> Bool {
    index < 64 ? low & (1 << index) != 0 : high & (1 << (index - 64)) != 0
  }
}

/// The language that `xml:lang` or `lang` of an element gives it, as `xml:lang` comes first in HTML.
enum ElementLanguage: Sendable, Equatable {
  /// The element has neither, and takes the language of its parent.
  case inherited
  /// An empty value makes the language unknown, without the language of the parent.
  case unknown
  /// A language in the canonical case of BCP 47, such as `zh-Hant` for `zh-HANT`, which Core Text takes.
  case language(Language)

  init(attributes: [String: String]) {
    guard let value = attributes["xml:lang"] ?? attributes["lang"] else {
      self = .inherited
      return
    }
    let language = value.trimmingCharacters(in: .whitespaces)
    self = language.isEmpty ? .unknown : .language(Language(Locale.canonicalLanguageIdentifier(from: language)))
  }

  /// The language of the element whose parent has the computed values.
  func resolved(parent: ComputedStyle?) -> Language? {
    switch self {
    case .inherited: parent?.language
    case .unknown: nil
    case .language(let language): language
    }
  }
}

/// A language tag as a number of the tags that the process has seen, so that the computed values that keep it stay
/// trivial to copy: a `String` in them made copying them a few percent slower.
struct Language: Sendable, Hashable {
  private let index: UInt16

  /// The tags by their numbers, and the numbers by their tags. A document has few languages, and the tags that more
  /// than the numbers can count share the last number.
  private static let tags = Mutex<(tags: [String], numbers: [String: UInt16])>(([], [:]))

  init(_ tag: String) {
    index = Self.tags.withLock { tags in
      if let number = tags.numbers[tag] { return number }
      guard tags.tags.count < Int(UInt16.max) else { return UInt16.max - 1 }
      let number = UInt16(tags.tags.count)
      tags.tags.append(tag)
      tags.numbers[tag] = number
      return number
    }
  }

  /// The tag, such as `ja` or `zh-Hant`.
  var tag: String {
    Self.tags.withLock { $0.tags[Int(index)] }
  }
}
