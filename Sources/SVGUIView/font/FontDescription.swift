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

    static func platformResolveGenericFamily(script: UScriptCode, locale: String?, familyName: String) -> String? {
        precondition((locale == nil && script == .common) || locale != nil)
        guard let locale = locale else { return nil }
        switch familyName {
        case SVGUIView.familyNamesData[.serif]:
            return SystemFontDatabaseCoreText.shared.serifFamily(locale: locale)
        case SVGUIView.familyNamesData[.sansSerif]:
            return SystemFontDatabaseCoreText.shared.sansSerifFamily(locale: locale)
        case SVGUIView.familyNamesData[.cursive]:
            return SystemFontDatabaseCoreText.shared.cursiveFamily(locale: locale)
        case SVGUIView.familyNamesData[.fantasy]:
            return SystemFontDatabaseCoreText.shared.fantasyFamily(locale: locale)
        case SVGUIView.familyNamesData[.monospace]:
            return SystemFontDatabaseCoreText.shared.monospaceFamily(locale: locale)
        default:
            return nil
        }
    }

    static func localeToScriptCodeForFontSelection(locale: String) -> UScriptCode {
        let canonicalLocale = locale.replacingOccurrences(of: "-", with: "_")
        if let scriptCode = Self.localeScriptMap[canonicalLocale] {
            return scriptCode
        }
        return .common
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
