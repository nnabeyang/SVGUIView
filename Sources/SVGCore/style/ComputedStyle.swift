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
  case clipRule = "clip-rule"
  case textAnchor = "text-anchor"
  case visibility
  case colorInterpolation = "color-interpolation"
  case colorInterpolationFilters = "color-interpolation-filters"
  case opacity
  case transform
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
    case .clipRule: visitor.visit(ClipRuleProperty.self)
    case .textAnchor: visitor.visit(TextAnchorProperty.self)
    case .visibility: visitor.visit(VisibilityProperty.self)
    case .colorInterpolation: visitor.visit(ColorInterpolationProperty.self)
    case .colorInterpolationFilters: visitor.visit(ColorInterpolationFiltersProperty.self)
    case .opacity: visitor.visit(OpacityProperty.self)
    case .transform: visitor.visit(TransformProperty.self)
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
struct ComputedStyle: Sendable {
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
  var strokeDasharray: [CGFloat]
  var strokeDashoffset: CGFloat
  var clipRule: FillRule
  var textAnchor: TextAnchor
  var visibility: CSSVisibility
  var colorInterpolation: SVGColorInterpolation?
  var colorInterpolationFilters: SVGColorInterpolation?
  var opacity: Double
  var transform: CGAffineTransform
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

  /// The initial value of every property, which is the style of the parent of the root element.
  static let initial = ComputedStyle(
    fontFamily: FontFamilyProperty.initial, fontSize: FontSizeProperty.initial,
    fontWeight: FontWeightProperty.initial, writingMode: WritingModeProperty.initial, color: ColorProperty.initial,
    fill: FillProperty.initial, fillOpacity: FillOpacityProperty.initial, fillRule: FillRuleProperty.initial,
    stroke: StrokeProperty.initial, strokeOpacity: StrokeOpacityProperty.initial,
    strokeWidth: StrokeWidthProperty.initial, strokeLinecap: StrokeLinecapProperty.initial,
    strokeLinejoin: StrokeLinejoinProperty.initial, strokeMiterlimit: StrokeMiterlimitProperty.initial,
    strokeDasharray: StrokeDasharrayProperty.initial, strokeDashoffset: StrokeDashoffsetProperty.initial,
    clipRule: ClipRuleProperty.initial, textAnchor: TextAnchorProperty.initial,
    visibility: VisibilityProperty.initial, colorInterpolation: ColorInterpolationProperty.initial,
    colorInterpolationFilters: ColorInterpolationFiltersProperty.initial, opacity: OpacityProperty.initial,
    transform: TransformProperty.initial, clipPath: ClipPathProperty.initial, mask: MaskProperty.initial,
    filter: FilterProperty.initial, display: DisplayProperty.initial, overflow: OverflowProperty.initial,
    stopColor: StopColorProperty.initial, stopOpacity: StopOpacityProperty.initial,
    floodColor: FloodColorProperty.initial, floodOpacity: FloodOpacityProperty.initial, x: XProperty.initial,
    y: YProperty.initial, width: WidthProperty.initial, height: HeightProperty.initial)

  /// The computed values of an element with the given cascaded values.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent element, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  init(cascaded: CascadedValues, parent: ComputedStyle?, root: ComputedStyle?) {
    var computer = Computer(
      cascaded: cascaded, resolver: StyleResolver(style: .initial, parent: parent ?? .initial, root: root ?? .initial))
    for id in PropertyID.allCases {
      id.visit(&computer)
    }
    self = computer.resolver.style
  }

  /// Computes the computed values in order, one property at a time, into the style of the resolver, so that
  /// computing a value doesn't copy the styles.
  private struct Computer: StylePropertyVisitor {
    let cascaded: CascadedValues
    var resolver: StyleResolver

    mutating func visit<P: StyleProperty>(_: P.Type) {
      let value: P.Computed =
        switch cascaded[P.self] {
        case .value(let value): P.compute(value, in: resolver)
        case .inherit: resolver.parent[keyPath: P.computed]
        case .initial: P.initial
        case .unset, nil: P.isInherited ? resolver.parent[keyPath: P.computed] : P.initial
        }
      resolver.style[keyPath: P.computed] = value
    }
  }

  private init(
    fontFamily: String, fontSize: SVGUIFont.Size, fontWeight: SVGUIFont.Weight, writingMode: WritingMode,
    color: SVGColor, fill: Paint, fillOpacity: Double, fillRule: FillRule, stroke: Paint, strokeOpacity: Double,
    strokeWidth: SVGLength, strokeLinecap: CGLineCap, strokeLinejoin: CGLineJoin, strokeMiterlimit: Double,
    strokeDasharray: [CGFloat], strokeDashoffset: CGFloat, clipRule: FillRule, textAnchor: TextAnchor,
    visibility: CSSVisibility, colorInterpolation: SVGColorInterpolation?,
    colorInterpolationFilters: SVGColorInterpolation?, opacity: Double, transform: CGAffineTransform,
    clipPath: SVGClipPath, mask: SVGMask, filter: SVGFilter, display: CSSDisplay, overflow: SVGOverflow?,
    stopColor: ColorValue, stopOpacity: Double, floodColor: ColorValue, floodOpacity: Double, x: SVGLength?,
    y: SVGLength?, width: SVGLength?, height: SVGLength?
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
    self.clipRule = clipRule
    self.textAnchor = textAnchor
    self.visibility = visibility
    self.colorInterpolation = colorInterpolation
    self.colorInterpolationFilters = colorInterpolationFilters
    self.opacity = opacity
    self.transform = transform
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
  }

  /// The font, with its size resolved except for viewport units.
  var font: SVGUIFont {
    SVGUIFont(name: fontFamily, size: fontSize, weight: fontWeight)
  }

  /// The paint with `currentColor` resolved.
  func resolved(_ paint: Paint) -> Paint {
    if case .currentColor = paint { return .color(color) }
    return paint
  }

  /// The color with `currentColor` resolved.
  func resolved(_ value: ColorValue) -> SVGColor {
    switch value {
    case .color(let color): color
    case .currentColor: color
    }
  }
}
