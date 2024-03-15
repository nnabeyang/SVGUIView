import _SPI

struct FontPlatformData: Hashable {
    struct FontVariationAxis {
        let name: String
        let tag: String
        let defaultValue: Double
        let minimumValue: Double
        let maximumValue: Double
    }

    struct Attributes {
        let size: Double = 0
        var orientation: FontOrientation { .horizontal }
        var widthVariant: FontWidthVariant { .regular }
        var syntheticBold: Bool { false }
        var syntheticOblique: Bool { false }
        let attributes: [CFString: Any]
        let options: CTFontDescriptorOptions
        let url: CFString
        let psName: CFString
    }

    var font: CTFont
    var size: Double = 0
    var orientation: FontOrientation = .horizontal
    var widthVariant: FontWidthVariant = .regular

    var syntheticBold: Bool = false
    var syntheticOblique: Bool = false
    var isColorBitmapFont: Bool = false
}
