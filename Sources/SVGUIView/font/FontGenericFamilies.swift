import _ICU

typealias ScriptFontFamilyMap = [Int: String]

class FontGenericFamilies {
  var standardFontFamilyMap = ScriptFontFamilyMap()
  var serifFontFamilyMap = ScriptFontFamilyMap()
  var fixedFontFamilyMap = ScriptFontFamilyMap()
  var sansSerifFontFamilyMap = ScriptFontFamilyMap()
  var cursiveFontFamilyMap = ScriptFontFamilyMap()
  var fantasyFontFamilyMap = ScriptFontFamilyMap()
  var pictographFontFamilyMap = ScriptFontFamilyMap()

  func fontFamily(family: FamilyNamesIndex, script: UScriptCode) -> String? {
    switch family {
    case .cursive:
      return cursiveFontFamily(script: script)
    case .fantasy:
      return fantasyFontFamily(script: script)
    case .monospace:
      return fixedFontFamily(script: script)
    case .pictograph:
      return pictographFontFamily(script: script)
    case .sansSerif:
      return sansSerifFontFamily(script: script)
    case .serif:
      return serifFontFamily(script: script)
    case .standard:
      return standardFontFamily(script: script)
    case .systemUi:
      return nil
    }
  }

  static func setGenericFontFamilyForScript(fontMap: inout ScriptFontFamilyMap, family: String, script: UScriptCode) -> Bool {
    if family.isEmpty {
      return fontMap.removeValue(forKey: Int(script.rawValue)) != nil
    }
    let key = Int(script.rawValue)
    if fontMap[key] != nil {
      return false
    }
    fontMap[key] = family
    return true
  }

  static func genericFontFamilyForScript(fontMap: ScriptFontFamilyMap, script: UScriptCode) -> String? {
    fontMap[Int(script.rawValue)]
  }

  func standardFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: standardFontFamilyMap, script: script)
  }

  func fixedFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: fixedFontFamilyMap, script: script)
  }

  func serifFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: serifFontFamilyMap, script: script)
  }

  func sansSerifFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: sansSerifFontFamilyMap, script: script)
  }

  func cursiveFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: cursiveFontFamilyMap, script: script)
  }

  func fantasyFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: fantasyFontFamilyMap, script: script)
  }

  func pictographFontFamily(script: UScriptCode) -> String? {
    Self.genericFontFamilyForScript(fontMap: pictographFontFamilyMap, script: script)
  }

  func setStandardFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &standardFontFamilyMap, family: family, script: script)
  }

  func setFixedFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &fixedFontFamilyMap, family: family, script: script)
  }

  func setSerifFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &serifFontFamilyMap, family: family, script: script)
  }

  func setSansSerifFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &sansSerifFontFamilyMap, family: family, script: script)
  }

  func setCursiveFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &cursiveFontFamilyMap, family: family, script: script)
  }

  func setFantasyFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &fantasyFontFamilyMap, family: family, script: script)
  }

  func setPictographFontFamily(family: String, script: UScriptCode) -> Bool {
    Self.setGenericFontFamilyForScript(fontMap: &pictographFontFamilyMap, family: family, script: script)
  }
}
