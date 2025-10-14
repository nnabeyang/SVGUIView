class FontCreationContextRareData: Equatable {
  var fontFaceFeatures: FontFeatureSettings
  var sizeAdjust: Double
  init(fontFaceFeatures: FontFeatureSettings, sizeAdjust: Double) {
    self.fontFaceFeatures = fontFaceFeatures
    self.sizeAdjust = sizeAdjust
  }

  static func == (lhs: FontCreationContextRareData, rhs: FontCreationContextRareData) -> Bool {
    lhs.fontFaceFeatures == rhs.fontFaceFeatures
      && lhs.sizeAdjust == rhs.sizeAdjust
  }
}
