import _SPI
import CoreText

class FontDatabase {
    class InstalledFont {
        var fontDescriptor: CTFontDescriptor
        var capabilities: FontSelectionCapabilities
        init(fontDescriptor: CTFontDescriptor, capabilities: FontSelectionCapabilities) {
            self.fontDescriptor = fontDescriptor
            self.capabilities = capabilities
        }

        convenience init(fontDescriptor: CTFontDescriptor) {
            let capabilities = VariationCapabilities.capabilitiesForFontDescriptor(fontDescriptor: fontDescriptor)
            self.init(fontDescriptor: fontDescriptor, capabilities: capabilities)
        }
    }

    class InstalledFontFamily {
        var installedFonts: [InstalledFont]
        var capabilities = FontSelectionCapabilities()
        init(installedFonts: [InstalledFont] = []) {
            self.installedFonts = installedFonts
            for font in installedFonts {
                expand(other: font)
            }
        }

        func expand(other: InstalledFont) {
            capabilities.expand(other: other.capabilities)
        }

        var isEmpty: Bool {
            installedFonts.isEmpty
        }
    }

    var allowUserInstalledFonts: AllowUserInstalledFonts
    var familyNameToFontDescriptors = [String: InstalledFontFamily]()

    init(allowUserInstalledFonts: AllowUserInstalledFonts) {
        self.allowUserInstalledFonts = allowUserInstalledFonts
    }

    func collectionForFamily(familyName: String) -> InstalledFontFamily {
        let folded = FontCascadeDescription.foldedFamilyName(familyName)
        if let fontFamily = familyNameToFontDescriptors[folded] { return fontFamily }
        let fontFamily: InstalledFontFamily = {
            let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: folded as CFString]
            let fontDescriptorToMatch = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            let mandatoryAttributes = Self.installedFontMandatoryAttributes(allowUserInstalledFonts: allowUserInstalledFonts)
            if let matches = CTFontDescriptorCreateMatchingFontDescriptors(fontDescriptorToMatch, mandatoryAttributes) {
                let count = CFArrayGetCount(matches)
                var result = [InstalledFont]()
                for i in 0 ..< count {
                    let fontDescriptor = unsafeBitCast(CFArrayGetValueAtIndex(matches, i), to: CTFontDescriptor.self)
                    result.append(InstalledFont(fontDescriptor: fontDescriptor))
                }
                return InstalledFontFamily(installedFonts: result)
            }
            return InstalledFontFamily()
        }()
        familyNameToFontDescriptors[folded] = fontFamily
        return fontFamily
    }

    func fontForPostScriptName(postScriptName: String) -> InstalledFont? {
        let folded = FontCascadeDescription.foldedFamilyName(postScriptName)
        var attributes: [CFString: Any] = [:]
        attributes[kCTFontEnabledAttribute] = kCFBooleanTrue
        attributes[kCTFontPostScriptNameAttribute] = folded as CFString
        SystemFontDatabaseCoreText.addAttributesForInstalledFonts(attributes: &attributes, allowUserInstalledFonts: allowUserInstalledFonts)
        let fontDescriptorToMatch = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let mandatoryAttributes = Self.installedFontMandatoryAttributes(allowUserInstalledFonts: allowUserInstalledFonts)
        guard let match = CTFontDescriptorCreateMatchingFontDescriptor(fontDescriptorToMatch, mandatoryAttributes) else {
            return nil
        }
        return InstalledFont(fontDescriptor: match)
    }

    static func installedFontMandatoryAttributes(allowUserInstalledFonts: AllowUserInstalledFonts) -> CFSet? {
        guard allowUserInstalledFonts == .no else { return nil }
        let mandatoryAttributesValues: Set = [kCTFontFamilyNameAttribute, kCTFontPostScriptNameAttribute, kCTFontEnabledAttribute, kCTFontUserInstalledAttribute, kCTFontFallbackOptionAttribute]
        return mandatoryAttributesValues as CFSet
    }
}
