class FontRanges {
    var ranges: [Range]
    var isGeneric: Bool

    init(ranges: [FontRanges.Range] = [Range](), isGeneric: Bool = false) {
        self.ranges = ranges
        self.isGeneric = isGeneric
    }

    init(other: FontRanges, isGeneric: Bool) {
        ranges = other.ranges
        self.isGeneric = isGeneric
    }

    convenience init(font: Font?) {
        var ranges = [Range]()
        if let font = font {
            ranges.append(Range(from: 0, to: 0x7FFF_FFFF, fontAccessor: TrivialFontAccessor(font: font)))
        }
        self.init(ranges: ranges)
    }

    var isNull: Bool {
        ranges.isEmpty
    }

    struct Range {
        var from: UInt32
        var to: UInt32
        var fontAccessor: FontAccessor

        func font(policy: ExternalResourceDownloadPolicy) -> Font? {
            fontAccessor.font(policy: policy)
        }
    }

    func glyphDataForCharacter(character: UInt32, policy: ExternalResourceDownloadPolicy) -> GlyphData {
        var resultFont: Font? = nil
        var policy = policy
        for range in ranges {
            if range.from <= character, character <= range.to {
                if let font = range.font(policy: policy) {
                    if font.isInterstitial {
                        policy = .forbid
                        if resultFont == nil {
                            resultFont = font
                        }
                    } else {
                        let glyphData = font.glyphDataForCharacter(character: character)
                        if let glyphDataFont = glyphData.font {
                            if glyphDataFont.visibility == .visible, let resultFont = resultFont, resultFont.visibility == .invisible {
                                return GlyphData(glyph: glyphData.glyph, font: glyphDataFont.invisibleFont)
                            }
                            return glyphData
                        }
                    }
                }
            }
        }
        if let resultFont = resultFont {
            var result = resultFont.glyphDataForCharacter(character: character)
            if !result.isValid {
                result.font = resultFont
            }
            return result
        }
        return GlyphData()
    }
}

class TrivialFontAccessor: FontAccessor {
    private var font: Font

    init(font: Font) {
        self.font = font
    }

    func font(policy _: ExternalResourceDownloadPolicy) -> Font {
        font
    }
}
