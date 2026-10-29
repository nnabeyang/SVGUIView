import CoreGraphics
import Foundation
import _CSSParser

// The properties that styles set. Each property is described here, and nowhere else.

private func scanning<T>(_ text: String, _ body: (inout SVGAttributeScanner) -> T) -> T {
  var data = text.trimmingCharacters(in: .whitespacesAndNewlines)
  return data.withUTF8 {
    var scanner = SVGAttributeScanner(bytes: BufferView(unsafeBufferPointer: $0)!)
    return body(&scanner)
  }
}

private func number(_ text: String) -> Double? {
  scanning(text) { $0.scanNumber() }
}

/// A keyword of the given type. Keywords in CSS are case-insensitive, and presentation attributes take them as
/// they're written.
private func keyword<T: RawRepresentable & CaseIterable>(_ text: String, origin: DeclarationOrigin) -> T?
where T.RawValue == String {
  let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  switch origin {
  case .attribute:
    return T(rawValue: text)
  case .css:
    return T.allCases.first { $0.rawValue.lowercased() == text.lowercased() }
  }
}

/// A length relative to a font, such as `2em`, in pixels, and any other length as it is. A length relative to a
/// font whose size is in viewport units stays as it is too, since the viewport is known only when drawing.
private func resolvingFontRelative(_ length: SVGLength, in resolver: StyleResolver) -> SVGLength {
  let isRoot = if case .rems = length { true } else if case .rlhs = length { true } else { false }
  switch (isRoot ? resolver.root : resolver.style).fontSize {
  case .length(.vw), .length(.vh), .length(.vi), .length(.vb), .length(.vmin), .length(.vmax):
    return length
  default:
    break
  }
  switch length {
  case .ems, .rems, .exs, .chs, .ic, .lhs, .rlhs:
    let context = FontLengthContext(font: resolver.style.font, rootFont: resolver.root.font)
    return .pixel(length.value(total: 0, context: context))
  default:
    return length
  }
}

/// What a length relative to a font needs: the font and the font of the root element. Fonts in viewport units
/// are measured with an empty viewport.
private struct FontLengthContext: SVGLengthContext {
  let font: SVGUIFont?
  let rootFont: SVGUIFont?
  var viewBoxSize: CGSize { .zero }
  var textScale: Double { 1 }
  var viewPort: CGRect { .zero }
  var writingMode: WritingMode? { nil }
}

/// An opacity of an animation, which an easing function can take outside 0 to 1, clamped to that range.
private func clampedOpacity(_ opacity: Double) -> Double {
  min(max(opacity, 0), 1)
}

enum FontFamilyProperty: StyleProperty {
  static let id = PropertyID.fontFamily
  static let isInherited = true
  static var initial: String { FontCacheCoreText.familyNamesData[.standard] }
  static let computed = \ComputedStyle.fontFamily

  static func parse(_ text: String, origin _: DeclarationOrigin) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}

enum FontSizeProperty: StyleProperty {
  static let id = PropertyID.fontSize
  static let isInherited = true
  static let initial = SVGUIFont.Size.medium
  static let computed = \ComputedStyle.fontSize

  static func parse(_ text: String, origin: DeclarationOrigin) -> SVGUIFont.Size? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return SVGUIFont.Size(rawValue: origin == .css ? text.lowercased() : text)
  }

  /// The size in pixels, or in viewport units, which can only be resolved when drawing. A keyword, such as
  /// `medium`, stays a keyword, which is resolved with the element's own font family, since `monospace` has
  /// smaller sizes.
  static func compute(_ size: SVGUIFont.Size, in resolver: StyleResolver) -> SVGUIFont.Size {
    let parent = resolver.parent.fontSize
    switch size {
    case .xxSmall, .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
      return size
    case .smaller:
      return scaled(parent, by: 1 / 1.2, family: resolver.parent.fontFamily)
    case .larger:
      return scaled(parent, by: 1.2, family: resolver.parent.fontFamily)
    case .length(let length):
      switch length {
      case .number(let value), .pixel(let value):
        return .length(.pixel(value))
      case .percent(let value):
        return scaled(parent, by: value / 100, family: resolver.parent.fontFamily)
      case .ems(let value):
        return scaled(parent, by: value, family: resolver.parent.fontFamily)
      case .rems(let value):
        return scaled(resolver.root.fontSize, by: value, family: resolver.root.fontFamily)
      case .vw, .vh, .vi, .vb, .vmin, .vmax:
        return size
      case .exs, .chs, .ic, .lhs, .rlhs:
        // Measure the font of the parent, or of the root for `rlh`. A font in viewport units is measured at
        // 100 pixels, and the size stays in its unit.
        let isRoot = if case .rlhs = length { true } else { false }
        let base = isRoot ? resolver.root : resolver.parent
        switch base.fontSize {
        case .length(.vw), .length(.vh), .length(.vi), .length(.vb), .length(.vmin), .length(.vmax):
          var reference = base
          reference.fontSize = .length(.pixel(100))
          let context = FontLengthContext(font: reference.font, rootFont: reference.font)
          return scaled(base.fontSize, by: length.value(total: 0, context: context) / 100, family: base.fontFamily)
        default:
          let context = FontLengthContext(font: base.font, rootFont: base.font)
          return .length(.pixel(length.value(total: 0, context: context)))
        }
      case .centimeters, .millimeters, .inches, .points, .picas, .q:
        return .length(.pixel(length.value(total: 0, context: FontLengthContext(font: nil, rootFont: nil))))
      }
    }
  }

  /// The size multiplied by the factor, in the same unit, or in pixels for a keyword.
  private static func scaled(_ size: SVGUIFont.Size, by factor: CGFloat, family: String) -> SVGUIFont.Size {
    switch size {
    case .length(.vw(let value)): .length(.vw(value * factor))
    case .length(.vh(let value)): .length(.vh(value * factor))
    case .length(.vi(let value)): .length(.vi(value * factor))
    case .length(.vb(let value)): .length(.vb(value * factor))
    case .length(.vmin(let value)): .length(.vmin(value * factor))
    case .length(.vmax(let value)): .length(.vmax(value * factor))
    default:
      .length(.pixel(SVGUIFont(name: family, size: size, weight: .normal).sizeValue(context: FontLengthContext(font: nil, rootFont: nil)) * factor))
    }
  }

  /// The size between two sizes, which isn't negative.
  static func interpolated(
    _ from: SVGUIFont.Size, _ to: SVGUIFont.Size, progress: Double, in _: StyleResolver
  ) -> SVGUIFont.Size {
    let size = from.animated(to: to, progress: progress)
    if case .length(let length) = size { return .length(length.nonNegative) }
    return size
  }

  /// The sum of two sizes, which isn't negative.
  static func added(_ value: SVGUIFont.Size, to underlying: SVGUIFont.Size, in _: StyleResolver) -> SVGUIFont.Size? {
    guard let size = underlying.adding(value) else { return nil }
    if case .length(let length) = size { return .length(length.nonNegative) }
    return size
  }
}

enum FontWeightProperty: StyleProperty {
  static let id = PropertyID.fontWeight
  static let isInherited = true
  static let initial = SVGUIFont.Weight.normal
  static let computed = \ComputedStyle.fontWeight

  static func parse(_ text: String, origin: DeclarationOrigin) -> SVGUIFont.Weight? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return SVGUIFont.Weight(rawValue: origin == .css ? text.lowercased() : text)
  }

  static func compute(_ weight: SVGUIFont.Weight, in resolver: StyleResolver) -> SVGUIFont.Weight {
    SVGUIFont.Weight(child: weight, parent: resolver.parent.fontWeight) ?? weight
  }
}

enum WritingModeProperty: StyleProperty {
  static let id = PropertyID.writingMode
  static let isInherited = true
  static let initial = WritingMode.horizontalTB
  static let computed = \ComputedStyle.writingMode

  static func parse(_ text: String, origin: DeclarationOrigin) -> WritingMode? {
    keyword(text, origin: origin)
  }
}

enum ColorProperty: StyleProperty {
  static let id = PropertyID.color
  static let isInherited = true
  static var initial: SVGColor { .named(SVGColorName(name: "black")) }
  static let computed = \ComputedStyle.color

  static func parse(_ text: String, origin _: DeclarationOrigin) -> ColorValue? {
    ColorValue(text)
  }

  /// The color, where `currentColor` is the color of the parent.
  static func compute(_ value: ColorValue, in resolver: StyleResolver) -> SVGColor {
    resolver.parent.resolved(value)
  }
}

enum FillProperty: StyleProperty {
  static let id = PropertyID.fill
  static let isInherited = true
  static var initial: Paint { .color(.named(SVGColorName(name: "black"))) }
  static let computed = \ComputedStyle.fill

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Paint? {
    Paint(text)
  }

  /// The paint between two paints, with `currentColor` as the color of the element, which can be animated too.
  static func interpolates(_ from: Paint, _ to: Paint, in resolver: StyleResolver) -> Bool {
    resolver.style.resolved(from).interpolated(to: resolver.style.resolved(to), progress: 0.5) != nil
  }

  static func interpolated(_ from: Paint, _ to: Paint, progress: Double, in resolver: StyleResolver) -> Paint {
    resolver.style.resolved(from).animated(to: resolver.style.resolved(to), progress: progress)
  }

  static func added(_ value: Paint, to underlying: Paint, in resolver: StyleResolver) -> Paint? {
    resolver.style.resolved(underlying).adding(resolver.style.resolved(value))
  }

  static func distance(_ from: Paint, _ to: Paint, in resolver: StyleResolver) -> Double? {
    resolver.style.resolved(from).pacedDistance(to: resolver.style.resolved(to))
  }
}

enum FillOpacityProperty: StyleProperty {
  static let id = PropertyID.fillOpacity
  static let isInherited = true
  static let initial = 1.0
  static let computed = \ComputedStyle.fillOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
  }

  static func interpolated(_ from: Double, _ to: Double, progress: Double, in _: StyleResolver) -> Double {
    clampedOpacity(from.animated(to: to, progress: progress))
  }

  static func added(_ value: Double, to underlying: Double, in _: StyleResolver) -> Double? {
    clampedOpacity(underlying + value)
  }
}

enum FillRuleProperty: StyleProperty {
  static let id = PropertyID.fillRule
  static let isInherited = true
  static let initial = FillRule.nonzero
  static let computed = \ComputedStyle.fillRule

  static func parse(_ text: String, origin: DeclarationOrigin) -> FillRule? {
    keyword(text, origin: origin)
  }
}

enum StrokeProperty: StyleProperty {
  static let id = PropertyID.stroke
  static let isInherited = true
  static let initial = Paint.none
  static let computed = \ComputedStyle.stroke

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Paint? {
    Paint(text)
  }

  /// The paint between two paints, with `currentColor` as the color of the element, which can be animated too.
  static func interpolates(_ from: Paint, _ to: Paint, in resolver: StyleResolver) -> Bool {
    resolver.style.resolved(from).interpolated(to: resolver.style.resolved(to), progress: 0.5) != nil
  }

  static func interpolated(_ from: Paint, _ to: Paint, progress: Double, in resolver: StyleResolver) -> Paint {
    resolver.style.resolved(from).animated(to: resolver.style.resolved(to), progress: progress)
  }

  static func added(_ value: Paint, to underlying: Paint, in resolver: StyleResolver) -> Paint? {
    resolver.style.resolved(underlying).adding(resolver.style.resolved(value))
  }

  static func distance(_ from: Paint, _ to: Paint, in resolver: StyleResolver) -> Double? {
    resolver.style.resolved(from).pacedDistance(to: resolver.style.resolved(to))
  }
}

enum StrokeOpacityProperty: StyleProperty {
  static let id = PropertyID.strokeOpacity
  static let isInherited = true
  static let initial = 1.0
  static let computed = \ComputedStyle.strokeOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
  }

  static func interpolated(_ from: Double, _ to: Double, progress: Double, in _: StyleResolver) -> Double {
    clampedOpacity(from.animated(to: to, progress: progress))
  }

  static func added(_ value: Double, to underlying: Double, in _: StyleResolver) -> Double? {
    clampedOpacity(underlying + value)
  }
}

enum StrokeWidthProperty: StyleProperty {
  static let id = PropertyID.strokeWidth
  static let isInherited = true
  static let initial = SVGLength.number(1)
  static let computed = \ComputedStyle.strokeWidth

  static func parse(_ text: String, origin _: DeclarationOrigin) -> SVGLength? {
    SVGLength(text)
  }

  static func compute(_ width: SVGLength, in resolver: StyleResolver) -> SVGLength {
    resolvingFontRelative(width, in: resolver)
  }

  /// The width between two widths, which isn't negative.
  static func interpolated(_ from: SVGLength, _ to: SVGLength, progress: Double, in _: StyleResolver) -> SVGLength {
    from.animated(to: to, progress: progress).nonNegative
  }

  /// The sum of two widths, which isn't negative.
  static func added(_ value: SVGLength, to underlying: SVGLength, in _: StyleResolver) -> SVGLength? {
    underlying.adding(value)?.nonNegative
  }
}

enum StrokeLinecapProperty: StyleProperty {
  static let id = PropertyID.strokeLinecap
  static let isInherited = true
  static let initial = CGLineCap.butt
  static let computed = \ComputedStyle.strokeLinecap

  static func parse(_ text: String, origin: DeclarationOrigin) -> CGLineCap? {
    switch keyword(text, origin: origin) as LineCap? {
    case .butt: .butt
    case .round: .round
    case .square: .square
    case nil: nil
    }
  }

  private enum LineCap: String, CaseIterable {
    case butt, round, square
  }
}

enum StrokeLinejoinProperty: StyleProperty {
  static let id = PropertyID.strokeLinejoin
  static let isInherited = true
  static let initial = CGLineJoin.miter
  static let computed = \ComputedStyle.strokeLinejoin

  static func parse(_ text: String, origin: DeclarationOrigin) -> CGLineJoin? {
    switch keyword(text, origin: origin) as LineJoin? {
    case .miter: .miter
    case .round: .round
    case .bevel: .bevel
    case nil: nil
    }
  }

  private enum LineJoin: String, CaseIterable {
    case miter, round, bevel
  }
}

enum StrokeMiterlimitProperty: StyleProperty {
  static let id = PropertyID.strokeMiterlimit
  static let isInherited = true
  static let initial = 4.0
  static let computed = \ComputedStyle.strokeMiterlimit

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    number(text)
  }

  /// The limit between two limits, which is at least 1.
  static func interpolated(_ from: Double, _ to: Double, progress: Double, in _: StyleResolver) -> Double {
    max(from.animated(to: to, progress: progress), 1)
  }

  /// The sum of two limits, which is at least 1.
  static func added(_ value: Double, to underlying: Double, in _: StyleResolver) -> Double? {
    max(underlying + value, 1)
  }
}

enum StrokeDasharrayProperty: StyleProperty {
  static let id = PropertyID.strokeDasharray
  static let isInherited = true
  static let initial: [CGFloat] = []
  static let computed = \ComputedStyle.strokeDasharray

  /// The dashes, or no dashes for `none`.
  static func parse(_ text: String, origin _: DeclarationOrigin) -> [CGFloat]? {
    if keyword(text) == "none" { return [] }
    let dashes = scanning(text) { $0.scanDashes() }
    return dashes.isEmpty ? nil : dashes
  }

  /// The dashes between two lists of dashes, which aren't negative.
  static func interpolated(_ from: [CGFloat], _ to: [CGFloat], progress: Double, in _: StyleResolver) -> [CGFloat] {
    from.animated(to: to, progress: progress).map { max($0, 0) }
  }

  /// The sum of two lists of dashes, which aren't negative.
  static func added(_ value: [CGFloat], to underlying: [CGFloat], in _: StyleResolver) -> [CGFloat]? {
    underlying.adding(value)?.map { max($0, 0) }
  }
}

enum StrokeDashoffsetProperty: StyleProperty {
  static let id = PropertyID.strokeDashoffset
  static let isInherited = true
  static let initial: CGFloat = 0
  static let computed = \ComputedStyle.strokeDashoffset

  static func parse(_ text: String, origin _: DeclarationOrigin) -> CGFloat? {
    number(text).map { CGFloat($0) }
  }
}

enum ClipRuleProperty: StyleProperty {
  static let id = PropertyID.clipRule
  static let isInherited = true
  static let initial = FillRule.nonzero
  static let computed = \ComputedStyle.clipRule

  static func parse(_ text: String, origin: DeclarationOrigin) -> FillRule? {
    keyword(text, origin: origin)
  }
}

enum TextAnchorProperty: StyleProperty {
  static let id = PropertyID.textAnchor
  static let isInherited = true
  static let initial = TextAnchor.start
  static let computed = \ComputedStyle.textAnchor

  static func parse(_ text: String, origin: DeclarationOrigin) -> TextAnchor? {
    keyword(text, origin: origin)
  }
}

enum WhiteSpaceProperty: StyleProperty {
  static let id = PropertyID.whiteSpace
  static let isInherited = true
  static let initial = CSSWhiteSpace.normal
  static let computed = \ComputedStyle.whiteSpace

  static func parse(_ text: String, origin: DeclarationOrigin) -> CSSWhiteSpace? {
    keyword(text, origin: origin)
  }
}

enum VisibilityProperty: StyleProperty {
  static let id = PropertyID.visibility
  static let isInherited = true
  static let initial = CSSVisibility.visible
  static let computed = \ComputedStyle.visibility
  /// SMIL animations change keywords discretely, as SVG says. CSS animations interpolate with the rules of CSS.
  static let isInterpolable = false

  static func parse(_ text: String, origin: DeclarationOrigin) -> CSSVisibility? {
    keyword(text, origin: origin)
  }
}

/// `color-interpolation`, whose computed value is `nil` where no element declares it, so that each element can
/// choose the color space it uses then.
enum ColorInterpolationProperty: StyleProperty {
  static let id = PropertyID.colorInterpolation
  static let isInherited = true
  static let initial: SVGColorInterpolation? = nil
  static let computed = \ComputedStyle.colorInterpolation

  static func parse(_ text: String, origin: DeclarationOrigin) -> SVGColorInterpolation?? {
    (keyword(text, origin: origin) as SVGColorInterpolation?).map { .some($0) }
  }
}

/// `color-interpolation-filters`, whose computed value is `nil` where no element declares it, so that each filter
/// primitive can choose the color space it uses then.
enum ColorInterpolationFiltersProperty: StyleProperty {
  static let id = PropertyID.colorInterpolationFilters
  static let isInherited = true
  static let initial: SVGColorInterpolation? = nil
  static let computed = \ComputedStyle.colorInterpolationFilters

  static func parse(_ text: String, origin: DeclarationOrigin) -> SVGColorInterpolation?? {
    (keyword(text, origin: origin) as SVGColorInterpolation?).map { .some($0) }
  }
}

enum OpacityProperty: StyleProperty {
  static let id = PropertyID.opacity
  static let isInherited = false
  static let initial = 1.0
  static let computed = \ComputedStyle.opacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
  }

  static func interpolated(_ from: Double, _ to: Double, progress: Double, in _: StyleResolver) -> Double {
    clampedOpacity(from.animated(to: to, progress: progress))
  }

  static func added(_ value: Double, to underlying: Double, in _: StyleResolver) -> Double? {
    clampedOpacity(underlying + value)
  }
}

enum TransformProperty: StyleProperty {
  static let id = PropertyID.transform
  static let isInherited = false
  static let initial = TransformList.none
  static let computed = \ComputedStyle.transform

  static func parse(_ text: String, origin: DeclarationOrigin) -> TransformList? {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    return TransformList.parse(&input, origin: origin)
  }

  static func parse(css input: inout _CSSParser.Parser) -> TransformList? {
    TransformList.parse(&input, origin: .css)
  }

  /// The list with lengths relative to a font in pixels. Percentages are of the reference box, which is known only
  /// when drawing.
  static func compute(_ list: TransformList, in resolver: StyleResolver) -> TransformList {
    TransformList(
      functions: list.functions.map {
        guard case .translate(let x, let y) = $0 else { return $0 }
        return .translate(resolvingFontRelative(x, in: resolver), resolvingFontRelative(y, in: resolver))
      })
  }
}

enum TransformOriginProperty: StyleProperty {
  static let id = PropertyID.transformOrigin
  static let isInherited = false
  static let initial = TransformOrigin.zero
  static let computed = \ComputedStyle.transformOrigin

  static func parse(_ text: String, origin: DeclarationOrigin) -> TransformOrigin? {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    return TransformOrigin.parse(&input, origin: origin)
  }

  static func parse(css input: inout _CSSParser.Parser) -> TransformOrigin? {
    TransformOrigin.parse(&input, origin: .css)
  }

  /// The origin with lengths relative to a font in pixels.
  static func compute(_ origin: TransformOrigin, in resolver: StyleResolver) -> TransformOrigin {
    TransformOrigin(x: resolvingFontRelative(origin.x, in: resolver), y: resolvingFontRelative(origin.y, in: resolver))
  }
}

/// The reference box of transforms. It isn't a presentation attribute.
enum TransformBoxProperty: StyleProperty {
  static let id = PropertyID.transformBox
  static let isInherited = false
  static let initial = TransformBox.viewBox
  static let computed = \ComputedStyle.transformBox

  static func accepts(attributeOn _: SVGElementName) -> Bool {
    false
  }

  static func parse(_ text: String, origin: DeclarationOrigin) -> TransformBox? {
    keyword(text, origin: origin)
  }

  /// The box of an SVG element: an SVG element has no box of CSS layout, so `content-box` is `fill-box`, and
  /// `border-box` is `stroke-box`.
  static func compute(_ box: TransformBox, in _: StyleResolver) -> TransformBox {
    switch box {
    case .contentBox: .fillBox
    case .borderBox: .strokeBox
    default: box
    }
  }
}

enum ClipPathProperty: StyleProperty {
  static let id = PropertyID.clipPath
  static let isInherited = false
  static let initial = SVGClipPath.none
  static let computed = \ComputedStyle.clipPath

  static func parse(_ text: String, origin _: DeclarationOrigin) -> SVGClipPath? {
    SVGClipPath(description: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

enum MaskProperty: StyleProperty {
  static let id = PropertyID.mask
  static let isInherited = false
  static let initial = SVGMask.none
  static let computed = \ComputedStyle.mask

  static func parse(_ text: String, origin _: DeclarationOrigin) -> SVGMask? {
    SVGMask(description: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

enum FilterProperty: StyleProperty {
  static let id = PropertyID.filter
  static let isInherited = false
  static let initial = SVGFilter.none
  static let computed = \ComputedStyle.filter

  static func parse(_ text: String, origin _: DeclarationOrigin) -> SVGFilter? {
    SVGFilter(description: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

enum DisplayProperty: StyleProperty {
  static let id = PropertyID.display
  static let isInherited = false
  static let initial = CSSDisplay.inline
  static let computed = \ComputedStyle.display

  static func parse(_ text: String, origin: DeclarationOrigin) -> CSSDisplay? {
    keyword(text, origin: origin)
  }

  /// One of the values, which is the one that isn't `none` between `none` and another value, so that an element
  /// shows while it's animated to or from `none`, as CSS Display specifies. Other values change halfway.
  static func interpolated(_ from: CSSDisplay, _ to: CSSDisplay, progress: Double, in _: StyleResolver) -> CSSDisplay {
    guard from != to, from == .none || to == .none else { return discrete(from, to, progress: progress) }
    if progress <= 0 { return from }
    if progress >= 1 { return to }
    return from == .none ? to : from
  }
}

/// `overflow`, whose computed value is `nil` where the element doesn't declare it, so that each element can choose
/// its default, such as `hidden` for an `<svg>` element.
enum OverflowProperty: StyleProperty {
  static let id = PropertyID.overflow
  static let isInherited = false
  static let initial: SVGOverflow? = nil
  static let computed = \ComputedStyle.overflow

  static func parse(_ text: String, origin: DeclarationOrigin) -> SVGOverflow?? {
    (keyword(text, origin: origin) as SVGOverflow?).map { .some($0) }
  }
}

enum StopColorProperty: StyleProperty {
  static let id = PropertyID.stopColor
  static let isInherited = false
  static var initial: ColorValue { .color(.named(SVGColorName(name: "black"))) }
  static let computed = \ComputedStyle.stopColor

  static func parse(_ text: String, origin _: DeclarationOrigin) -> ColorValue? {
    ColorValue(text)
  }

  /// The color between two colors, with `currentColor` as the color of the element, which can be animated too.
  static func interpolates(_ from: ColorValue, _ to: ColorValue, in resolver: StyleResolver) -> Bool {
    resolver.style.resolved(from).interpolated(to: resolver.style.resolved(to), progress: 0.5) != nil
  }

  static func interpolated(
    _ from: ColorValue, _ to: ColorValue, progress: Double, in resolver: StyleResolver
  ) -> ColorValue {
    .color(resolver.style.resolved(from).animated(to: resolver.style.resolved(to), progress: progress))
  }

  static func added(_ value: ColorValue, to underlying: ColorValue, in resolver: StyleResolver) -> ColorValue? {
    resolver.style.resolved(underlying).adding(resolver.style.resolved(value)).map { .color($0) }
  }

  static func distance(_ from: ColorValue, _ to: ColorValue, in resolver: StyleResolver) -> Double? {
    resolver.style.resolved(from).pacedDistance(to: resolver.style.resolved(to))
  }
}

enum StopOpacityProperty: StyleProperty {
  static let id = PropertyID.stopOpacity
  static let isInherited = false
  static let initial = 1.0
  static let computed = \ComputedStyle.stopOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
  }

  static func interpolated(_ from: Double, _ to: Double, progress: Double, in _: StyleResolver) -> Double {
    clampedOpacity(from.animated(to: to, progress: progress))
  }

  static func added(_ value: Double, to underlying: Double, in _: StyleResolver) -> Double? {
    clampedOpacity(underlying + value)
  }
}

enum FloodColorProperty: StyleProperty {
  static let id = PropertyID.floodColor
  static let isInherited = false
  static var initial: ColorValue { .color(.named(SVGColorName(name: "black"))) }
  static let computed = \ComputedStyle.floodColor

  static func parse(_ text: String, origin _: DeclarationOrigin) -> ColorValue? {
    ColorValue(text)
  }

  /// The color between two colors, with `currentColor` as the color of the element, which can be animated too.
  static func interpolates(_ from: ColorValue, _ to: ColorValue, in resolver: StyleResolver) -> Bool {
    resolver.style.resolved(from).interpolated(to: resolver.style.resolved(to), progress: 0.5) != nil
  }

  static func interpolated(
    _ from: ColorValue, _ to: ColorValue, progress: Double, in resolver: StyleResolver
  ) -> ColorValue {
    .color(resolver.style.resolved(from).animated(to: resolver.style.resolved(to), progress: progress))
  }

  static func added(_ value: ColorValue, to underlying: ColorValue, in resolver: StyleResolver) -> ColorValue? {
    resolver.style.resolved(underlying).adding(resolver.style.resolved(value)).map { .color($0) }
  }

  static func distance(_ from: ColorValue, _ to: ColorValue, in resolver: StyleResolver) -> Double? {
    resolver.style.resolved(from).pacedDistance(to: resolver.style.resolved(to))
  }
}

enum FloodOpacityProperty: StyleProperty {
  static let id = PropertyID.floodOpacity
  static let isInherited = false
  static let initial = 1.0
  static let computed = \ComputedStyle.floodOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
  }

  static func interpolated(_ from: Double, _ to: Double, progress: Double, in _: StyleResolver) -> Double {
    clampedOpacity(from.animated(to: to, progress: progress))
  }

  static func added(_ value: Double, to underlying: Double, in _: StyleResolver) -> Double? {
    clampedOpacity(underlying + value)
  }
}

/// A geometry property of `<rect>`, whose computed value is `nil` for `auto`. Other elements read these attributes
/// themselves, and style sheets don't change them.
protocol RectGeometryProperty: StyleProperty where Specified == SVGLength, Computed == SVGLength? {}

extension RectGeometryProperty {
  static var isInherited: Bool { false }
  static var initial: SVGLength? { nil }

  static func accepts(attributeOn name: SVGElementName) -> Bool {
    name == .rect
  }

  static func parse(_ text: String, origin _: DeclarationOrigin) -> SVGLength? {
    SVGLength(text)
  }

  static func compute(_ length: SVGLength, in resolver: StyleResolver) -> SVGLength? {
    resolvingFontRelative(length, in: resolver)
  }
}

enum XProperty: RectGeometryProperty {
  static let id = PropertyID.x
  static let computed = \ComputedStyle.x
}

enum YProperty: RectGeometryProperty {
  static let id = PropertyID.y
  static let computed = \ComputedStyle.y
}

enum WidthProperty: RectGeometryProperty {
  static let id = PropertyID.width
  static let computed = \ComputedStyle.width
}

enum HeightProperty: RectGeometryProperty {
  static let id = PropertyID.height
  static let computed = \ComputedStyle.height
}

/// The path data of `<path>`, which is the only element that has it.
enum DProperty: StyleProperty {
  static let id = PropertyID.d
  static let isInherited = false
  static let initial = PathData.none
  static let computed = \ComputedStyle.d

  static func accepts(attributeOn name: SVGElementName) -> Bool {
    name == .path
  }

  /// The path data of the attribute up to its first error, as SVG specifies, or the value in CSS.
  static func parse(_ text: String, origin: DeclarationOrigin) -> PathData? {
    switch origin {
    case .attribute:
      return PathData(text)
    case .css:
      var input = _CSSParser.Parser(input: ParserInput(input: text))
      return PathData.parse(&input)
    }
  }

  static func parse(css input: inout _CSSParser.Parser) -> PathData? {
    PathData.parse(&input)
  }
}
