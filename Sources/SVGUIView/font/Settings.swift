import _ICU

class Settings {
  var values = Values()
  init() {
    initializeDefaultFontFamilies()
  }

  var fontGenericFamilies: FontGenericFamilies {
    values.fontGenericFamilies
  }

  func initializeDefaultFontFamilies() {
    setStandardFontFamily(family: "PingFang TC", script: .hant)
    setStandardFontFamily(family: "PingFang SC", script: .hans)
    setStandardFontFamily(family: "Hiragino Mincho ProN", script: .kana)
    setStandardFontFamily(family: "Apple SD Gothic Neo", script: .hang)

    setStandardFontFamily(family: "Times", script: .common)
    setFixedFontFamily(family: "Courier", script: .common)
    setSerifFontFamily(family: "Times", script: .common)
    setSansSerifFontFamily(family: "Helvetica", script: .common)

    setPictographFontFamily(family: "AppleColorEmoji", script: .common)
    setCursiveFontFamily(family: "Snell Roundhand", script: .common)
    setFantasyFontFamily(family: "Papyrus", script: .common)
  }

  func standardFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.standardFontFamily(script: script)
  }

  func setStandardFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setStandardFontFamily(family: family, script: script)
  }

  func fixedFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.fixedFontFamily(script: script)
  }

  func setFixedFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setFixedFontFamily(family: family, script: script)
  }

  func serifFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.serifFontFamily(script: script)
  }

  func setSerifFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setSerifFontFamily(family: family, script: script)
  }

  func sansSerifFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.sansSerifFontFamily(script: script)
  }

  func setSansSerifFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setSansSerifFontFamily(family: family, script: script)
  }

  func cursiveFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.cursiveFontFamily(script: script)
  }

  func setCursiveFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setCursiveFontFamily(family: family, script: script)
  }

  func fantasyFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.fantasyFontFamily(script: script)
  }

  func setFantasyFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setFantasyFontFamily(family: family, script: script)
  }

  func pictographFontFamily(script: UScriptCode) -> String? {
    fontGenericFamilies.pictographFontFamily(script: script)
  }

  func setPictographFontFamily(family: String, script: UScriptCode) {
    _ = fontGenericFamilies.setPictographFontFamily(family: family, script: script)
  }

  struct Values {
    var fontGenericFamilies = FontGenericFamilies()
  }
}
