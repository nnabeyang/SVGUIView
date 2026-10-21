import CoreText

struct FontFamilySpecificationKey: Hashable {
  let fontDescriptor: CTFontDescriptor
  let fontDescriptorKey: FontDescriptionKey

  init(fontDescriptor: CTFontDescriptor, fontDescriptorKey: FontDescriptionKey) {
    self.fontDescriptor = fontDescriptor
    self.fontDescriptorKey = fontDescriptorKey
  }

  init(fontDescriptor: CTFontDescriptor, fontDescription: FontDescription) {
    self.fontDescriptor = fontDescriptor
    fontDescriptorKey = FontDescriptionKey(description: fontDescription)
  }

  static func == (lhs: FontFamilySpecificationKey, rhs: FontFamilySpecificationKey) -> Bool {
    lhs.fontDescriptor == rhs.fontDescriptor && lhs.fontDescriptorKey == rhs.fontDescriptorKey
  }

  var isHashTableDeletedValue: Bool {
    fontDescriptorKey.isDeletedValue
  }
}
