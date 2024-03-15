import CoreText

class Font {
    typealias Origin = FontOrigin
    typealias Attributes = FontInternalAttributes
    typealias Visibility = FontVisibility
    typealias IsInterstitial = FontIsInterstitial
    typealias IsOrientationFallback = FontIsOrientationFallback
    struct DerivedFonts {
        var smallCapsFont: Font?
        var noSynthesizableFeaturesFont: Font?
        var emphasisMarkFont: Font?
        var brokenIdeographFont: Font?
        var verticalRightOrientationFont: Font?
        var uprightOrientationFont: Font?
        var invisibleFont: Font?
    }

    lazy var derivedFonts: DerivedFonts = .init()

    var platformData: FontPlatformData
    var attributes: Attributes
    var hasVerticalGlyphs = false
    var glyphPages = [UInt: GlyphPage]()
    init(platformData: FontPlatformData, origin: Origin = .local, interstitial: IsInterstitial = .no,
         visibility: Visibility = .visible, orientationFallback: IsOrientationFallback = .no)
    {
        self.platformData = platformData
        attributes = Attributes(origin: origin, isInterstitial: interstitial, visibility: visibility, isTextOrientationFallback: orientationFallback)
    }

    var ctFont: CTFont {
        platformData.font
    }

    var origin: Origin { attributes.origin }
    var isInterstitial: Bool {
        attributes.isInterstitial == .yes
    }

    var visibility: Visibility {
        attributes.visibility
    }

    var invisibleFont: Font {
        if let font = derivedFonts.invisibleFont {
            return font
        }
        let font = Font(platformData: platformData, origin: origin, interstitial: .yes, visibility: .invisible)
        derivedFonts.invisibleFont = font
        return font
    }

    func glyphDataForCharacter(character: UInt32) -> GlyphData {
        guard let page = glyphPage(pageNumber: UInt(character)) else {
            return GlyphData()
        }
        return page.glyphDataForCharacter(character)
    }

    func glyphPage(pageNumber: UInt) -> GlyphPage? {
        if let page = glyphPages[pageNumber] {
            return page
        }
        let page = Self.createAndFillGlyphPage(pageNumber: pageNumber, font: self)
        glyphPages[pageNumber] = page
        return page
    }

    static func isBMP(_ c: UInt32) -> Bool {
        c <= 0xFFFF
    }

    static func createAndFillGlyphPage(pageNumber: UInt, font: Font) -> GlyphPage? {
        let glyphPageSize = GlyphPage.sizeForPageNumber(pageNumber: pageNumber)
        let start = GlyphPage.startingCodePointInPageNumber(pageNumber: pageNumber)
        var buffer = [UInt16](repeating: 0, count: Int(glyphPageSize) * 2 + 2)
        let bufferLength: Int
        if Self.isBMP(UInt32(start)) {
            bufferLength = Int(glyphPageSize)
            for i in 0 ..< bufferLength {
                buffer[i] = UInt16(start) + UInt16(i)
            }
        } else {
            bufferLength = Int(glyphPageSize) * 2
            for i in 0 ..< bufferLength {
                let c = UInt32(start) + UInt32(i)
                buffer[i] = UInt16((c >> 10) + 0xD7C0) // U16_LEAD
                buffer[i] = UInt16((c & 0x3FF) | 0xDC00) // U16_TRAIL
            }
        }
        let glyphPage = GlyphPage(font: font)
        guard Self.fillGlyphPage(pageToFill: glyphPage, buffer: &buffer, bufferLength: bufferLength) else { return nil }
        return glyphPage
    }

    static func fillGlyphPage(pageToFill: GlyphPage, buffer: inout [UInt16], bufferLength: Int) -> Bool {
        pageToFill.fill(buffer: &buffer, bufferLength: bufferLength)
    }
}

enum FontOrigin {
    case remote
    case local
}

enum FontIsInterstitial {
    case no
    case yes
}

enum FontVisibility {
    case visible
    case invisible
}

enum FontIsOrientationFallback {
    case no
    case yes
}

struct FontInternalAttributes {
    let origin: FontOrigin
    let isInterstitial: FontIsInterstitial
    let visibility: FontVisibility
    let isTextOrientationFallback: FontIsOrientationFallback
}
