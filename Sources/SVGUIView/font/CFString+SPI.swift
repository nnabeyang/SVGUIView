public import CoreFoundation
public import CoreText

public var kCTFontCSSWeightAttribute: CFString { "CTFontCSSWeightAttribute" as CFString }
public var kCTFontCSSWidthAttribute: CFString { "CTFontCSSWidthAttribute" as CFString }
public var kCTFontDescriptorTextStyleAttribute: CFString { "NSCTFontUIUsageAttribute" as CFString }
public var kCTFontUIFontDesignTrait: CFString { "NSCTFontUIFontDesignTrait" as CFString }

public var kCTFontPostScriptNameAttribute: CFString { "NSCTFontPostScriptNameAttribute" as CFString }
public var kCTFontUserInstalledAttribute: CFString { "NSCTFontUserInstalledAttribute" as CFString }
public var kCTFontFallbackOptionAttribute: CFString { "NSCTFontFallbackOptionAttribute" as CFString }

public var kCTFontUIFontDesignDefault: CFString { "NSCTFontUIFontDesignDefault" as CFString }
public var kCTFontUIFontDesignSerif: CFString { "NSCTFontUIFontDesignSerif" as CFString }
public var kCTFontUIFontDesignMonospaced: CFString { "NSCTFontUIFontDesignMonospaced" as CFString }
public var kCTFontUIFontDesignRounded: CFString { "NSCTFontUIFontDesignRounded" as CFString }

public let kCTFontWidthUltraCompressed: CGFloat = -0.5
public let kCTFontWidthExtraCompressed: CGFloat = -0.4
public let kCTFontWidthCompressed: CGFloat = -0.3
public let kCTFontWidthExtraCondensed: CGFloat = -0.3
public let kCTFontWidthCondensed: CGFloat = -0.2
public let kCTFontWidthSemiCondensed: CGFloat = -0.1
public let kCTFontWidthStandard: CGFloat = 0.0
public let kCTFontWidthSemiExpanded: CGFloat = 0.1
public let kCTFontWidthExpanded: CGFloat = 0.2
public let kCTFontWidthExtraExpanded: CGFloat = 0.3

public var kCTUIFontTextStyleShortHeadline: CFString { "UICTFontTextStyleShortHeadline" as CFString }
public var kCTUIFontTextStyleShortBody: CFString { "UICTFontTextStyleShortBody" as CFString }
public var kCTUIFontTextStyleShortSubhead: CFString { "UICTFontTextStyleShortSubhead" as CFString }
public var kCTUIFontTextStyleShortFootnote: CFString { "UICTFontTextStyleShortFootnote" as CFString }
public var kCTUIFontTextStyleShortCaption1: CFString { "UICTFontTextStyleShortCaption1" as CFString }
public var kCTUIFontTextStyleTallBody: CFString { "UICTFontTextStyleTallBody" as CFString }

public var kCTUIFontTextStyleHeadline: CFString { "UICTFontTextStyleHeadline" as CFString }
public var kCTUIFontTextStyleBody: CFString { "UICTFontTextStyleBody" as CFString }
public var kCTUIFontTextStyleSubhead: CFString { "UICTFontTextStyleSubhead" as CFString }
public var kCTUIFontTextStyleFootnote: CFString { "UICTFontTextStyleFootnote" as CFString }
public var kCTUIFontTextStyleCaption1: CFString { "UICTFontTextStyleCaption1" as CFString }
public var kCTUIFontTextStyleCaption2: CFString { "UICTFontTextStyleCaption2" as CFString }

public var kCTUIFontTextStyleTitle0: CFString { "UICTFontTextStyleTitle0" as CFString }
public var kCTUIFontTextStyleTitle1: CFString { "UICTFontTextStyleTitle1" as CFString }
public var kCTUIFontTextStyleTitle2: CFString { "UICTFontTextStyleTitle2" as CFString }
public var kCTUIFontTextStyleTitle3: CFString { "UICTFontTextStyleTitle3" as CFString }
public var kCTUIFontTextStyleTitle4: CFString { "UICTFontTextStyleTitle4" as CFString }

public var kCTFontCSSFamilySerif: CFString { "serif" as CFString }
public var kCTFontCSSFamilySansSerif: CFString { "sans-serif" as CFString }
public var kCTFontCSSFamilyCursive: CFString { "cursive" as CFString }
public var kCTFontCSSFamilyFantasy: CFString { "fantasy" as CFString }
public var kCTFontCSSFamilyMonospace: CFString { "monospace" as CFString }
public var kCTFontCSSFamilySystemUI: CFString { "system-ui" as CFString }

public func CTFontCreateLastResort(_ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    CTFontCreateWithName("LastResort" as CFString, size, matrix)
}

public func CTFontIsAppleColorEmoji(_ font: CTFont) -> Bool {
    CTFontCopyFullName(font) as String == "Apple Color Emoji"
}

public func CTFontDescriptorIsSystemUIFont(_ descriptor: CTFontDescriptor) -> Bool {
    switch CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
    case ".AppleSystemUIFont", ".AppleSystemUIFontMonospaced":
        return true
    default:
        return false
    }
}
