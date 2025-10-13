import _SPI
import Foundation

class FontCache {
    let fontFamilySpecificationCoreTextCache = FontFamilySpecificationCoreTextCache()
    let systemFontDatabaseCoreText = SystemFontDatabaseCoreText()
    var seenFamiliesForPrewarming = [String]()

    class FontDataCaches {
        private var platformData = [FontPlatformDataCacheKey: FontPlatformData]()
        private var data = [FontPlatformData: Font]()
        private let lock = NSLock()

        func platformData(for key: FontPlatformDataCacheKey) -> FontPlatformData? {
            lock.lock()
            defer { lock.unlock() }
            return platformData[key]
        }

        func platformData(_ value: FontPlatformData?, for key: FontPlatformDataCacheKey) {
            lock.lock()
            defer {
                lock.unlock()
            }
            platformData[key] = value
        }

        func data(for key: FontPlatformData) -> Font? {
            lock.lock()
            defer { lock.unlock() }
            return data[key]
        }

        func data(_ font: Font, for key: FontPlatformData) {
            lock.lock()
            defer {
                lock.unlock()
            }
            data[key] = font
        }
    }

    nonisolated(unsafe) static let shared = FontCache()
    var fontDataCaches = FontDataCaches()

    func createFontPlatformData(fontDescription: FontDescription, familyName: String, fontCreationContext: FontCreationContext) -> FontPlatformData? {
        let size = fontDescription.adjustedSizeForFontFace(fontFaceSizeAdjust: fontCreationContext.sizeAdjust)
        let fontDatabase = FontDatabase(allowUserInstalledFonts: fontDescription.shouldAllowUserInstalledFonts)
        guard let font = SVGUIView.fontWithFamily(fontDatabase: fontDatabase, familyName: familyName,
                                                  fontDescription: fontDescription, fontCreationContext: fontCreationContext, size: size)
        else {
            return nil
        }
        if fontDescription.shouldAllowUserInstalledFonts == .no {
            seenFamiliesForPrewarming.append(FontCascadeDescription.foldedFamilyName(familyName))
        }
        let (syntheticBold, syntheticOblique) = FontFamilySpecificationCoreText.computeNecessarySynthesis(font: font,
                                                                                                          fontDescription: fontDescription).boldObliquePair
        let platformData = FontPlatformData(font: font, size: size,
                                            orientation: fontDescription.orientation, widthVariant: fontDescription.widthVariant,
                                            syntheticBold: syntheticBold, syntheticOblique: syntheticOblique)
        return platformData
    }

    func fontForPlatformData(platformData: FontPlatformData) -> Font {
        let font = Font(platformData: platformData, origin: .local)
        fontDataCaches.data(font, for: platformData)
        return font
    }

    func cachedFontPlatformData(fontDescription: FontDescription, familyName: String,
                                fontCreationContext: FontCreationContext, checkingAlternateName: Bool = false) -> FontPlatformData?
    {
        let key = FontPlatformDataCacheKey(descriptionKey: .init(description: fontDescription),
                                           familyName: familyName, fontCreationContext: fontCreationContext)
        guard let value = fontDataCaches.platformData(for: key) else {
            let value = createFontPlatformData(fontDescription: fontDescription, familyName: familyName, fontCreationContext: fontCreationContext)
            fontDataCaches.platformData(value, for: key)
            if value == nil, !checkingAlternateName {
                if let alternateName = Self.alternateFamilyName(familyName: familyName) {
                    if let alternateData = cachedFontPlatformData(fontDescription: fontDescription, familyName: alternateName,
                                                                  fontCreationContext: fontCreationContext, checkingAlternateName: true)
                    {
                        fontDataCaches.platformData(alternateData, for: key)
                        return alternateData
                    }
                }
            }
            return value
        }
        return value
    }

    static func alternateFamilyName(familyName: String) -> String? {
        if let platformSpecificAlternate = Self.platformAlternateFamilyName(familyName: familyName) {
            return platformSpecificAlternate
        }
        switch familyName.utf16.count {
        case 5:
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "arial") {
                return "Helvetica"
            }
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "times") {
                return "Times New Roman"
            }
        case 7:
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "courier") {
                return "Courier New"
            }
        case 9:
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "helvetica") {
                return "Arial"
            }
        case 11:
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "courier new") {
                return "Courier"
            }
        case 15:
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "times new roman") {
                return "Times"
            }
        default:
            break
        }
        return nil
    }

    private static let heitiString: [UInt16] = [0x9ED1, 0x4F53]
    private static let songtiString: [UInt16] = [0x5B8B, 0x4F53]
    private static let weiruanXinXiMingTi: [UInt16] = [0x5FAE, 0x8EDF, 0x65B0, 0x7D30, 0x660E, 0x9AD4]
    private static let weiruanYaHeiString: [UInt16] = [0x5FAE, 0x8F6F, 0x96C5, 0x9ED1]
    private static let weiruanZhengHeitiString: [UInt16] = [0x5FAE, 0x8EDF, 0x6B63, 0x9ED1, 0x9AD4]

    private static let songtiSC = "Songti SC"
    private static let songtiTC = "Songti TC"
    private static let heitiSCReplacement = "PingFang SC"
    private static let heitiTCReplacement = "PingFang TC"

    static func platformAlternateFamilyName(familyName: String) -> String? {
        let bytes = Array(familyName.utf16)
        switch bytes.count {
        case 2:
            if bytes == Self.songtiString {
                return Self.songtiSC
            }
            if bytes == Self.heitiString {
                return Self.heitiSCReplacement
            }
        case 4:
            if bytes == Self.weiruanYaHeiString {
                return Self.heitiSCReplacement
            }
        default:
            break
        }
        return nil
    }

    static var matchWords: [String] {
        ["Arabic", "Pashto", "Urdu"]
    }

    func similarFont(description: FontDescription, familyName: String) -> Font? {
        guard familyName.isEmpty else { return nil }
        if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "monaco") ||
            SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "menlo")
        {
            return fontForFamily(fontDescription: description, familyName: "courier")
        }
        if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: "lucida grande") {
            return fontForFamily(fontDescription: description, familyName: "verdana")
        }
        for matchWord in Self.matchWords {
            if SVGUIView.equalLettersIgnoringASCIICase(string: familyName, literal: matchWord) {
                let name = FontSelectionValue.isFontWeightBold(fontWeight: description.weight) ? "GeezaPro-Bold" : "GeezaPro"
                return fontForFamily(fontDescription: description, familyName: name)
            }
        }
        return nil
    }

    func fontForFamily(fontDescription: FontDescription, familyName: String,
                       fontCreationContext: FontCreationContext = .init(), checkingAlternateName: Bool = false) -> Font?
    {
        guard let platformData = cachedFontPlatformData(fontDescription: fontDescription, familyName: familyName,
                                                        fontCreationContext: fontCreationContext, checkingAlternateName: checkingAlternateName)
        else {
            return nil
        }
        return fontForPlatformData(platformData: platformData)
    }

    func lastResortFallbackFont(fontDescription: FontDescription) -> Font {
        if let result = fontForFamily(fontDescription: fontDescription, familyName: "Times") {
            return result
        }
        let font = CTFontCreateLastResort(fontDescription.computedSize, nil)
        let (syntheticBold, syntheticOblique) = FontFamilySpecificationCoreText.computeNecessarySynthesis(font: font,
                                                                                                          fontDescription: fontDescription).boldObliquePair
        let platformData = FontPlatformData(font: font, size: fontDescription.computedSize,
                                            orientation: fontDescription.orientation, widthVariant: fontDescription.widthVariant,
                                            syntheticBold: syntheticBold, syntheticOblique: syntheticOblique)
        return fontForPlatformData(platformData: platformData)
    }
}

struct FontPlatformDataCacheKey: Hashable {
    var descriptionKey: FontDescriptionKey
    var familyName: String
    var fontCreationContext: FontCreationContext
}
