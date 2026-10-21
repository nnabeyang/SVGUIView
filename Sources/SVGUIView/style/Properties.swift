import CoreGraphics
import Foundation

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

/// A length relative to a font, such as `2em`, in pixels, and any other length as it is.
private func resolvingFontRelative(_ length: SVGLength, in resolver: StyleResolver) -> SVGLength {
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
        // Measure the font of the parent, or of the root for `rlh`, at 1 pixel, and scale its size.
        let isRoot = if case .rlhs = length { true } else { false }
        let base = isRoot ? resolver.root : resolver.parent
        var unit = base
        unit.fontSize = .length(.pixel(1))
        let context = FontLengthContext(font: unit.font, rootFont: unit.font)
        return scaled(base.fontSize, by: length.value(total: 0, context: context), family: base.fontFamily)
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
      .length(.pixel(SVGUIFont(name: family, size: size, weight: nil).sizeValue(context: FontLengthContext(font: nil, rootFont: nil)) * factor))
    }
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
}

enum FillOpacityProperty: StyleProperty {
  static let id = PropertyID.fillOpacity
  static let isInherited = true
  static let initial = 1.0
  static let computed = \ComputedStyle.fillOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
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
}

enum StrokeOpacityProperty: StyleProperty {
  static let id = PropertyID.strokeOpacity
  static let isInherited = true
  static let initial = 1.0
  static let computed = \ComputedStyle.strokeOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
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

enum VisibilityProperty: StyleProperty {
  static let id = PropertyID.visibility
  static let isInherited = true
  static let initial = CSSVisibility.visible
  static let computed = \ComputedStyle.visibility

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
}

enum TransformProperty: StyleProperty {
  static let id = PropertyID.transform
  static let isInherited = false
  static let initial = CGAffineTransform.identity
  static let computed = \ComputedStyle.transform

  static func parse(_ text: String, origin _: DeclarationOrigin) -> CGAffineTransform? {
    CGAffineTransform(description: text)
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
}

enum StopOpacityProperty: StyleProperty {
  static let id = PropertyID.stopOpacity
  static let isInherited = false
  static let initial = 1.0
  static let computed = \ComputedStyle.stopOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
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
}

enum FloodOpacityProperty: StyleProperty {
  static let id = PropertyID.floodOpacity
  static let isInherited = false
  static let initial = 1.0
  static let computed = \ComputedStyle.floodOpacity

  static func parse(_ text: String, origin _: DeclarationOrigin) -> Double? {
    SVGOpacity(text).map { Double($0.value) }
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
