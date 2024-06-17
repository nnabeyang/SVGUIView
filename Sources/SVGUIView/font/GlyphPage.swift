import _SPI
import CoreText

class GlyphPage {
    private static let size = 16
    let font: Font
    var glyphs = [Glyph](repeating: 0, count: GlyphPage.size)
    var isColor = [Bool](repeating: false, count: GlyphPage.size)
    init(font: Font) {
        self.font = font
    }

    static func sizeForPageNumber(pageNumber _: UInt) -> UInt { UInt(Self.size) }

    static func indexForCodePoint(_ c: UInt32) -> Int {
        Int(c) % Self.size
    }

    static func pageNumberForCodePoint(_ c: UInt32) -> UInt {
        UInt(c) / UInt(Self.size)
    }

    static func startingCodePointInPageNumber(pageNumber: UInt) -> UInt {
        pageNumber * UInt(Self.size)
    }

    func setGlyphForIndex(index: Int, glyph: Glyph, colorGlyphType: ColorGlyphType) {
        glyphs[index] = glyph
        isColor[index] = colorGlyphType == .color
    }

    func glyphDataForCharacter(_ c: UInt32) -> GlyphData {
        let index = Self.indexForCodePoint(c)
        return glyphDataForIndex(index: index)
    }

    func glyphDataForIndex(index: Int) -> GlyphData {
        let glyph = glyphs[index]
        let colorGlyphType: ColorGlyphType = isColor[index] ? .color : .outline
        return GlyphData(glyph: glyph, font: glyph == 0 ? nil : font, colorGlyphType: colorGlyphType)
    }

    static let deletedGlyph: CGGlyph = 0xFFFF
    func fill(buffer: inout [UInt16], bufferLength: Int) -> Bool {
        let ctFont = font.platformData.font
        var glyphs = [CGGlyph](repeating: 0, count: 512)
        CTFontGetGlyphsForCharacters(ctFont, buffer, &glyphs, bufferLength)
        let glyphStep = bufferLength / GlyphPage.size
        var haveGlyphs = false
        for i in 0 ..< GlyphPage.size {
            let theGlyph = glyphs[i * glyphStep]
            if theGlyph != Self.deletedGlyph {
                setGlyphForIndex(index: i, glyph: theGlyph, colorGlyphType: .outline)
                haveGlyphs = true
            }
        }
        return haveGlyphs
    }
}
