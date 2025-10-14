class CSSFontSelector: FontSelector {
  var settings = Settings()
  var familyNames = FamilyNames()

  init() {
    familyNames = SVGUIView.familyNamesData
  }

  func resolveGenericFamily(fontDescription: FontDescription, familyName: String) -> String? {
    let script = fontDescription.script
    if let familyNameIndex = familyNames.find(familyName) {
      if let familyString = settings.fontGenericFamilies.fontFamily(family: familyNameIndex, script: script) {
        return familyString
      }
    }
    return nil
  }

  func fontRangesForFamily(fontDescription: FontDescription, familyName: String) -> FontRanges {
    var familyForLookup = familyName
    var isGeneric = false
    if let genericFamily = resolveGenericFamily(fontDescription: fontDescription, familyName: familyName) {
      familyForLookup = genericFamily
      isGeneric = true
    }
    let font = FontCache.shared.fontForFamily(fontDescription: fontDescription, familyName: familyForLookup)
    return FontRanges(other: .init(font: font), isGeneric: isGeneric)
  }
}

struct FamilyNames: ExpressibleByArrayLiteral {
  private var storage = [String]()
  init(arrayLiteral elements: String...) {
    storage = elements
  }

  subscript(key: FamilyNamesIndex) -> String {
    storage[key.rawValue]
  }

  func find(_ name: String) -> FamilyNamesIndex? {
    let count = storage.count
    for i in 0..<count {
      let value = storage[i]
      if value == name {
        return FamilyNamesIndex(rawValue: i)
      }
    }
    return nil
  }
}

enum FamilyNamesIndex: Int {
  case cursive
  case fantasy
  case monospace
  case pictograph
  case sansSerif
  case serif
  case standard
  case systemUi
}
