class FontSelectionCapabilities {
  var weight: ClosedRange<FontSelectionValue> = .normalWeightValue ... .normalWeightValue
  var width: ClosedRange<FontSelectionValue> = .normalStretchValue ... .normalStretchValue
  var slope: ClosedRange<FontSelectionValue> = .normalItalicValue ... .normalItalicValue
  init() {}
  init(variation: VariationCapabilities) {
    weight = FontSelectionValue(variation.weight!.lowerBound)...FontSelectionValue(variation.weight!.upperBound)
    width = FontSelectionValue(variation.width!.lowerBound)...FontSelectionValue(variation.width!.upperBound)
    slope = FontSelectionValue(variation.slope!.lowerBound)...FontSelectionValue(variation.slope!.upperBound)
  }

  func expand(other: FontSelectionCapabilities) {
    weight = weight.expand(other: other.weight)
    width = width.expand(other: other.width)
    slope = slope.expand(other: other.slope)
  }
}
