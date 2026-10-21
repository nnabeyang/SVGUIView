class FontCreationContext: Hashable {
  var fontFaceCapabilities: FontSelectionSpecifiedCapabilities
  var rareData: FontCreationContextRareData?
  init(fontFaceCapabilities: FontSelectionSpecifiedCapabilities = .init(), rareData: FontCreationContextRareData? = nil) {
    self.rareData = rareData
    self.fontFaceCapabilities = fontFaceCapabilities
  }

  var sizeAdjust: Double {
    rareData?.sizeAdjust ?? 1.0
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(fontFaceCapabilities)
    hasher.combine(sizeAdjust)
  }

  static func == (lhs: FontCreationContext, rhs: FontCreationContext) -> Bool {
    lhs.fontFaceCapabilities == rhs.fontFaceCapabilities && lhs.rareData === rhs.rareData
  }
}
