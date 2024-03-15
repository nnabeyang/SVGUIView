class FontCascadeFonts {
    var fontSelector: FontSelector?
    var realizedFallbackRanges = [FontRanges]()
    var cachedPrimaryFont: Font?
    init(fontSelector: FontSelector) {
        self.fontSelector = fontSelector
    }

    func primaryFont(description: FontCascadeDescription) -> Font {
        if let font = cachedPrimaryFont { return font }
        let primaryRanges = realizeFallbackRangesAt(description: description, index: 0)
        cachedPrimaryFont = primaryRanges.glyphDataForCharacter(character: UnicodeScalar(" ").value, policy: .allow).font
        if let font = cachedPrimaryFont, font.isInterstitial {
            var index = 0
            while true {
                let localRanges = realizeFallbackRangesAt(description: description, index: index)
                if localRanges.isNull {
                    break
                }
                if let font = localRanges.glyphDataForCharacter(character: UnicodeScalar(" ").value, policy: .forbid).font,
                   font.isInterstitial
                {
                    cachedPrimaryFont = font
                    break
                }
                index += 1
            }
        } else if cachedPrimaryFont == nil {
            cachedPrimaryFont = primaryRanges.ranges[0].font(policy: .allow)
        }
        guard let font = cachedPrimaryFont else {
            fatalError()
        }
        return font
    }

    static func realizeNextFallback(description: FontCascadeDescription, fontSelector: FontSelector?) -> FontRanges {
        var index = 0
        let fontCache = FontCache.shared
        let count = description.effectiveFamilyCount
        while index < count {
            let currentFamily = description.effectiveFamilyAt(index: index)
            index += 1
            let fontRanges: FontRanges = {
                switch currentFamily {
                case let .string(family):
                    guard let family = family else {
                        return FontRanges()
                    }
                    if let fontSelector = fontSelector {
                        let ranges = fontSelector.fontRangesForFamily(fontDescription: description, familyName: family)
                        if !ranges.isNull {
                            return ranges
                        }
                    }
                    if let font = fontCache.fontForFamily(fontDescription: description, familyName: family) {
                        return FontRanges(font: font)
                    }
                    return FontRanges()
                case let .spec(fontFamilySpecification):
                    return FontRanges(other: fontFamilySpecification.fontRanges(fontDescription: description), isGeneric: true)
                }
            }()
            if !fontRanges.isNull {
                return fontRanges
            }
        }
        for familyName in description.familyNames {
            if let font = fontCache.similarFont(description: description, familyName: familyName) {
                return FontRanges(font: font)
            }
        }
        return FontRanges()
    }

    func realizeFallbackRangesAt(description: FontCascadeDescription, index: Int) -> FontRanges {
        var fontRanges = FontRanges()
        realizedFallbackRanges.append(fontRanges)
        guard index > 0 else {
            fontRanges = Self.realizeNextFallback(description: description, fontSelector: fontSelector)
            if fontRanges.isNull, let fontSelector = fontSelector {
                fontRanges = fontSelector.fontRangesForFamily(fontDescription: description,
                                                              familyName: SVGUIView.familyNamesData[.standard])
            }
            if fontRanges.isNull {
                fontRanges = FontRanges(font: FontCache.shared.lastResortFallbackFont(fontDescription: description))
            }
            return fontRanges
        }
        if description.effectiveFamilyCount > 0 {
            fontRanges = Self.realizeNextFallback(description: description, fontSelector: fontSelector)
        }
        return fontRanges
    }
}
