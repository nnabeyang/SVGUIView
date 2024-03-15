typealias Glyph = UInt16
enum ColorGlyphType: UInt8 {
    case outline
    case color
}

struct GlyphData {
    var glyph: Glyph
    let colorGlyphType: ColorGlyphType
    var font: Font?
    init(glyph: Glyph = 0, font: Font? = nil, colorGlyphType: ColorGlyphType = .outline) {
        self.glyph = glyph
        self.colorGlyphType = colorGlyphType
        self.font = font
    }

    var isValid: Bool { font != nil }
}
