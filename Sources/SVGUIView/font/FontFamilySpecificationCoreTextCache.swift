class FontFamilySpecificationCoreTextCache {
    static var shared: FontFamilySpecificationCoreTextCache {
        FontCache.shared.fontFamilySpecificationCoreTextCache
    }

    var fonts = [FontFamilySpecificationKey: FontPlatformData]()
}
