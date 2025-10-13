import _SPI
import CoreText
import UIKit

struct FontFamilySpecificationCoreText {
    let fontDescriptor: CTFontDescriptor
    func fontRanges(fontDescription: FontDescription) -> FontRanges {
        let size = fontDescription.computedSize

        let unrealizedFont = UnrealizedCoreTextFont(font: CTFontCreateWithFontDescriptor(fontDescriptor, size, nil))
        unrealizedFont.size = size
        let font = SVGUIView.preparePlatformFont(originalFont: unrealizedFont,
                                                 fontDescription: fontDescription, fontCreationContext: FontCreationContext(), fontTypeForPreparation: .systemFont)!
        let (syntheticBold, syntheticOblique) = Self.computeNecessarySynthesis(font: font, fontDescription: fontDescription)
            .boldObliquePair
        let platformData = FontPlatformData(font: font, size: size, orientation: fontDescription.orientation, widthVariant: fontDescription.widthVariant,
                                            syntheticBold: syntheticBold, syntheticOblique: syntheticOblique)
        let key = FontFamilySpecificationKey(fontDescriptor: fontDescriptor, fontDescription: fontDescription)
        FontFamilySpecificationCoreTextCache.shared.font(platformData, for: key)
        return FontRanges(font: FontCache.shared.fontForPlatformData(platformData: platformData))
    }

    static func computeNecessarySynthesis(font: CTFont, fontDescription: FontDescription, isPlatformFont: Bool = false) -> SynthesisPair
    {
        if CTFontIsAppleColorEmoji(font) {
            return SynthesisPair((false, false))
        }
        if isPlatformFont {
            return SynthesisPair((false, false))
        }
        let desiredTraits = Self.computeTraits(fontDescription: fontDescription)
        let actualTraits: CTFontSymbolicTraits
        if FontSelectionValue.isItalic(slope: fontDescription.italic) || FontSelectionValue.isFontWeightBold(fontWeight: fontDescription.weight) {
            actualTraits = CTFontGetSymbolicTraits(font)
        } else {
            actualTraits = .zero
        }

        let needsSyntheticBold = fontDescription.hasAutoFontSynthesisWeight
            && desiredTraits.contains(.traitBold)
            && !actualTraits.contains(.traitBold)
        let needsSyntheticOblique = fontDescription.hasAutoFontSynthesisStyle
            && desiredTraits.contains(.italicTrait)
            && !actualTraits.contains(.italicTrait)
        return SynthesisPair((needsSyntheticBold, needsSyntheticOblique))
    }

    static func computeTraits(fontDescription: FontDescription) -> CTFontSymbolicTraits {
        [
            FontSelectionValue.isItalic(slope: fontDescription.italic) ? .italicTrait : .zero,
            FontSelectionValue.isFontWeightBold(fontWeight: fontDescription.weight) ? .boldTrait : .zero,
        ]
    }
}

struct SynthesisPair {
    var needsSyntheticBold: Bool
    var needsSyntheticOblique: Bool
    init(needsSyntheticBold: Bool, needsSyntheticOblique: Bool) {
        self.needsSyntheticBold = needsSyntheticBold
        self.needsSyntheticOblique = needsSyntheticOblique
    }

    init(_ pair: (Bool, Bool)) {
        (needsSyntheticBold, needsSyntheticOblique) = pair
    }

    var boldObliquePair: (Bool, Bool) {
        (needsSyntheticBold, needsSyntheticOblique)
    }
}

enum ShouldComputePhysicalTraits {
    case no
    case yes
}

enum FontSynthesisLonghandValue {
    case no
    case auto
}
