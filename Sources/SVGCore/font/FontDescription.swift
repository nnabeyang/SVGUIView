import Foundation
import _ICU

class FontDescription {
  var sizeAdjust = FontSizeAdjust()
  var locale: String?
  var specifiedLocale: String = ""

  var fontSelectionRequest = FontSelectionRequest(
    weight: FontCascadeDescription.initialWeight,
    width: FontCascadeDescription.initialStretch,
    slope: FontCascadeDescription.initialItalic
  )

  var hasAutoFontSynthesisStyle: Bool {
    fontSynthesisStyle == .auto
  }

  var hasAutoFontSynthesisWeight: Bool {
    fontSynthesisWeight == .auto
  }

  var computedSize: Double = 0
  var orientation: FontOrientation = .horizontal
  var widthVariant: FontWidthVariant = .regular
  var script: UScriptCode = .common
  var fontSynthesisWeight: FontSynthesisLonghandValue = .auto
  var fontSynthesisStyle: FontSynthesisLonghandValue = .auto
  var fontStyleAxis: FontStyleAxis = FontCascadeDescription.initialFontStyleAxis
  var shouldAllowUserInstalledFonts: AllowUserInstalledFonts = .yes
  var italic: FontSelectionValue? { fontSelectionRequest.slope }
  var stretch: FontSelectionValue { fontSelectionRequest.width }
  var weight: FontSelectionValue { fontSelectionRequest.weight }

  func adjustedSizeForFontFace(fontFaceSizeAdjust: Double) -> Double {
    fontFaceSizeAdjust * computedSize
  }

  func setSpecifiedLocale(locale: String) {
    specifiedLocale = locale
    script = Self.localeToScriptCodeForFontSelection(locale: locale)
    self.locale = locale
  }

  static func localeToScriptCodeForFontSelection(locale: String) -> UScriptCode {
    var canonicalLocale = locale.replacingOccurrences(of: "-", with: "_")
    while !canonicalLocale.isEmpty {
      if let code = Self.localeScriptMap[canonicalLocale] {
        return code
      }
      guard let underScoreIndex = canonicalLocale.lastIndex(of: "_") else {
        break
      }
      let startIndex = canonicalLocale.index(after: underScoreIndex)
      let code = Self.scriptNameToCode(scriptName: String(canonicalLocale[startIndex...]))
      if code != .invalid, code != .common {
        return code
      }
      canonicalLocale = String(canonicalLocale[..<underScoreIndex])
    }
    return .common
  }

  static func scriptNameToCode(scriptName: String) -> UScriptCode {
    Self.scriptNameCodeMap[scriptName, default: .invalid]
  }

  static let localeScriptMap: [String: UScriptCode] = [
    "aa": .latn,
    "ab": .cyrl,
    "ady": .cyrl,
    "af": .latn,
    "ak": .latn,
    "am": .ethi,
    "ar": .arab,
    "as": .beng,
    "ast": .latn,
    "av": .cyrl,
    "ay": .latn,
    "az": .latn,
    "ba": .cyrl,
    "be": .cyrl,
    "bg": .cyrl,
    "bi": .latn,
    "bn": .beng,
    "bo": .tibt,
    "bs": .latn,
    "ca": .latn,
    "ce": .cyrl,
    "ceb": .latn,
    "ch": .latn,
    "chk": .latn,
    "cs": .latn,
    "cy": .latn,
    "da": .latn,
    "de": .latn,
    "dv": .thaa,
    "dz": .tibt,
    "ee": .latn,
    "efi": .latn,
    "el": .grek,
    "en": .latn,
    "es": .latn,
    "et": .latn,
    "eu": .latn,
    "fa": .arab,
    "fi": .latn,
    "fil": .latn,
    "fj": .latn,
    "fo": .latn,
    "fr": .latn,
    "fur": .latn,
    "fy": .latn,
    "ga": .latn,
    "gaa": .latn,
    "gd": .latn,
    "gil": .latn,
    "gl": .latn,
    "gn": .latn,
    "gsw": .latn,
    "gu": .gujr,
    "ha": .latn,
    "haw": .latn,
    "he": .hebr,
    "hi": .deva,
    "hil": .latn,
    "ho": .latn,
    "hr": .latn,
    "ht": .latn,
    "hu": .latn,
    "hy": .armn,
    "id": .latn,
    "ig": .latn,
    "ii": .yiii,
    "ilo": .latn,
    "inh": .cyrl,
    "is": .latn,
    "it": .latn,
    "iu": .cans,
    "ja": .kana,
    "jv": .latn,
    "ka": .geor,
    "kaj": .latn,
    "kam": .latn,
    "kbd": .cyrl,
    "kha": .latn,
    "kk": .cyrl,
    "kl": .latn,
    "km": .khmr,
    "kn": .knda,
    "ko": .hang,
    "kok": .deva,
    "kos": .latn,
    "kpe": .latn,
    "krc": .cyrl,
    "ks": .arab,
    "ku": .arab,
    "kum": .cyrl,
    "ky": .cyrl,
    "la": .latn,
    "lah": .arab,
    "lb": .latn,
    "lez": .cyrl,
    "ln": .latn,
    "lo": .laoo,
    "lt": .latn,
    "lv": .latn,
    "mai": .deva,
    "mdf": .cyrl,
    "mg": .latn,
    "mh": .latn,
    "mi": .latn,
    "mk": .cyrl,
    "ml": .mlym,
    "mn": .cyrl,
    "mr": .deva,
    "ms": .latn,
    "mt": .latn,
    "my": .mymr,
    "myv": .cyrl,
    "na": .latn,
    "nb": .latn,
    "ne": .deva,
    "niu": .latn,
    "nl": .latn,
    "nn": .latn,
    "nr": .latn,
    "nso": .latn,
    "ny": .latn,
    "oc": .latn,
    "om": .latn,
    "or": .orya,
    "os": .cyrl,
    "pa": .guru,
    "pag": .latn,
    "pap": .latn,
    "pau": .latn,
    "pl": .latn,
    "pon": .latn,
    "ps": .arab,
    "pt": .latn,
    "qu": .latn,
    "rm": .latn,
    "rn": .latn,
    "ro": .latn,
    "ru": .cyrl,
    "rw": .latn,
    "sa": .deva,
    "sah": .cyrl,
    "sat": .latn,
    "sd": .arab,
    "se": .latn,
    "sg": .latn,
    "si": .sinh,
    "sid": .latn,
    "sk": .latn,
    "sl": .latn,
    "sm": .latn,
    "so": .latn,
    "sq": .latn,
    "sr": .cyrl,
    "ss": .latn,
    "st": .latn,
    "su": .latn,
    "sv": .latn,
    "sw": .latn,
    "ta": .taml,
    "te": .telu,
    "tet": .latn,
    "tg": .cyrl,
    "th": .thai,
    "ti": .ethi,
    "tig": .ethi,
    "tk": .latn,
    "tkl": .latn,
    "tl": .latn,
    "tn": .latn,
    "to": .latn,
    "tpi": .latn,
    "tr": .latn,
    "trv": .latn,
    "ts": .latn,
    "tt": .cyrl,
    "tvl": .latn,
    "tw": .latn,
    "ty": .latn,
    "tyv": .cyrl,
    "udm": .cyrl,
    "ug": .arab,
    "uk": .cyrl,
    "und": .latn,
    "ur": .arab,
    "uz": .cyrl,
    "ve": .latn,
    "vi": .latn,
    "wal": .ethi,
    "war": .latn,
    "wo": .latn,
    "xh": .latn,
    "yap": .latn,
    "yo": .latn,
    "za": .latn,
    "zh": .hani,
    "zh_hk": .hant,
    "zh_tw": .hant,
    "zu": .latn,
  ]

  static let scriptNameCodeMap: [String: UScriptCode] = [
    "arab": .arab,
    "armn": .armn,
    "bali": .bali,
    "batk": .batk,
    "beng": .beng,
    "blis": .blis,
    "bopo": .bopo,
    "brah": .brah,
    "brai": .brai,
    "bugi": .bugi,
    "buhd": .buhd,
    "cans": .cans,
    "cham": .cham,
    "cher": .cher,
    "cirt": .cirt,
    "copt": .copt,
    "cprt": .cprt,
    "cyrl": .cyrl,
    "cyrs": .cyrs,
    "deva": .deva,
    "dsrt": .dsrt,
    "egyd": .egyd,
    "egyh": .egyh,
    "egyp": .egyp,
    "ethi": .ethi,
    "geok": .geok,
    "geor": .geor,
    "glag": .glag,
    "goth": .goth,
    "grek": .grek,
    "gujr": .gujr,
    "guru": .guru,
    "hang": .hang,
    "hani": .hani,
    "hano": .hano,
    "hans": .hans,
    "hant": .hant,
    "hebr": .hebr,
    "hira": .kana,
    "hmng": .hmng,
    "hrkt": .kana,
    "hung": .hung,
    "inds": .inds,
    "ital": .ital,
    "java": .java,
    "jpan": .kana,
    "kali": .kali,
    "kana": .kana,
    "khar": .khar,
    "khmr": .khmr,
    "knda": .knda,
    "kore": .hang,
    "laoo": .laoo,
    "latf": .latf,
    "latg": .latg,
    "latn": .latn,
    "lepc": .lepc,
    "limb": .limb,
    "lina": .lina,
    "linb": .linb,
    "mand": .mand,
    "maya": .maya,
    "mero": .mero,
    "mlym": .mlym,
    "mong": .mong,
    "mymr": .mymr,
    "nkoo": .nkoo,
    "ogam": .ogam,
    "orkh": .orkh,
    "orya": .orya,
    "osma": .osma,
    "perm": .perm,
    "phag": .phag,
    "phnx": .phnx,
    "plrd": .plrd,
    "qaai": .zinh,
    "roro": .roro,
    "runr": .runr,
    "sara": .sara,
    "shaw": .shaw,
    "sinh": .sinh,
    "sylo": .sylo,
    "syrc": .syrc,
    "syre": .syre,
    "syrj": .syrj,
    "syrn": .syrn,
    "tagb": .tagb,
    "tale": .tale,
    "talu": .talu,
    "taml": .taml,
    "telu": .telu,
    "teng": .teng,
    "tfng": .tfng,
    "tglg": .tglg,
    "thaa": .thaa,
    "thai": .thai,
    "tibt": .tibt,
    "ugar": .ugar,
    "vaii": .vaii,
    "visp": .visp,
    "xpeo": .xpeo,
    "xsux": .xsux,
    "yiii": .yiii,
    "zxxx": .zxxx,
    "zyyy": .common,
    "zzzz": .zzzz,
  ]
}

enum FontOrientation {
  case horizontal
  case vertical
}

enum NonCJKGlyphOrientation {
  case mixed
  case upright
}

enum FontWidthVariant: UInt8 {
  case regular
  case half
  case third
  case quarter
}
