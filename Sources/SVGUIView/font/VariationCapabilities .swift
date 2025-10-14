import CoreText
import Foundation
import _SPI

extension ClosedRange {
  init(bound: Bound) {
    self.init(uncheckedBounds: (lower: bound, upper: bound))
  }

  func expand(other: ClosedRange<Bound>) -> ClosedRange<Bound> {
    let lower = Swift.min(lowerBound, other.lowerBound)
    let upper = Swift.max(upperBound, other.upperBound)
    return ClosedRange(uncheckedBounds: (lower: lower, upper: upper))
  }
}

struct VariationCapabilities {
  var weight: ClosedRange<Double>?
  var width: ClosedRange<Double>?
  var slope: ClosedRange<Double>?

  init(weight: ClosedRange<Double>? = nil, width: ClosedRange<Double>? = nil, slope: ClosedRange<Double>? = nil) {
    self.weight = weight
    self.width = width
    self.slope = slope
  }

  static func extractVariationBounds(axis: [String: Any]) -> ClosedRange<Double>? {
    let minimumValue = (axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue ?? 0
    let maximumValue = (axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue ?? 0
    guard minimumValue < maximumValue else { return nil }
    return minimumValue...maximumValue
  }

  static func variationAxes(fontDescriptor: CTFontDescriptor) -> [[String: Any]]? {
    CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontVariationAxesAttribute) as? [[String: Any]]
  }

  static func variationCapabilitiesForFontDescriptor(fontDescriptor: CTFontDescriptor) -> VariationCapabilities {
    var result = VariationCapabilities()
    guard CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontVariationAttribute) != nil else { return result }
    guard let axes = Self.variationAxes(fontDescriptor: fontDescriptor) else { return result }
    for axis in axes {
      guard let axisIdentifier = (axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.int32Value else {
        continue
      }
      switch axisIdentifier {
      case 0x7767_6874:  // "wght"
        result.weight = extractVariationBounds(axis: axis)
      case 0x7764_7468:  // "wdth"
        result.width = extractVariationBounds(axis: axis)
      case 0x736C_6E74:  // "slnt"
        result.slope = extractVariationBounds(axis: axis)
      default:
        break
      }
    }
    let optOutFromGXNormalization = CTFontDescriptorIsSystemUIFont(fontDescriptor)
    let variationType: FontInterrogation.VariationType? = {
      let font = CTFontCreateWithFontDescriptor(fontDescriptor, 0, nil)
      return FontInterrogation(font: font).variationType
    }()

    if variationType == .trueTypeGX, !optOutFromGXNormalization {
      if let weight = result.weight {
        let minimum = FontInterrogation.normalizeGXWeight(weight.lowerBound)
        let maximum = FontInterrogation.normalizeGXWeight(weight.upperBound)
        result.weight = minimum...maximum
      }
      if let width = result.width {
        let minimum = FontInterrogation.normalizeVariationWidth(width.lowerBound)
        let maximum = FontInterrogation.normalizeVariationWidth(width.upperBound)
        result.width = minimum...maximum
      }
      if let slope = result.slope {
        let minimum = FontInterrogation.normalizeSlope(slope.lowerBound)
        let maximum = FontInterrogation.normalizeSlope(slope.upperBound)
        result.slope = minimum...maximum
      }
    }

    let maximum = FontSelectionValue.maximumValue.double
    let minimum = FontSelectionValue.minimumValue.double
    if let weight = result.weight, weight.lowerBound < minimum || weight.upperBound > maximum {
      result.weight = nil
    }
    if let width = result.width, width.lowerBound < minimum || width.upperBound > maximum {
      result.width = nil
    }
    if let slope = result.slope, slope.lowerBound < minimum || slope.upperBound > maximum {
      result.slope = nil
    }
    return result
  }

  static func getCSSAttribute(fontDescriptor: CTFontDescriptor, attribute: CFString, fallback: Double) -> Double {
    guard let number = CTFontDescriptorCopyAttribute(fontDescriptor, attribute) as? NSNumber else {
      return fallback
    }
    return number.doubleValue
  }

  static func capabilitiesForFontDescriptor(fontDescriptor: CTFontDescriptor?) -> FontSelectionCapabilities {
    guard let fontDescriptor = fontDescriptor else { return .init() }
    var variation = Self.variationCapabilitiesForFontDescriptor(fontDescriptor: fontDescriptor)
    if variation.slope == nil {
      guard let traits = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontTraitsAttribute) as? [CFString: Any] else {
        fatalError()
      }
      if let symbolicTraits = traits[kCTFontSymbolicTrait] as? NSNumber {
        let slopeValue = (symbolicTraits.int32Value & Int32(CTFontSymbolicTraits.italicTrait.rawValue) != 0) ? FontSelectionValue.italicValue.double : FontSelectionValue.normalItalicValue.double
        variation.slope = slopeValue...slopeValue
      } else {
        variation.slope = FontSelectionValue.normalItalicValue.double...FontSelectionValue.normalItalicValue.double
      }
    }
    if variation.weight == nil {
      let weight = Self.getCSSAttribute(fontDescriptor: fontDescriptor, attribute: kCTFontCSSWeightAttribute, fallback: FontSelectionValue.normalWeightValue.double)
      variation.weight = weight...weight
    }
    if variation.width == nil {
      let width = Self.getCSSAttribute(fontDescriptor: fontDescriptor, attribute: kCTFontCSSWidthAttribute, fallback: FontSelectionValue.normalStretchValue.double)
      variation.width = width...width
    }
    return FontSelectionCapabilities(variation: variation)
  }
}
