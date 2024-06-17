import CoreFoundation
import CoreText

public let kCTFontCSSWeightAttribute = "CTFontCSSWeightAttribute" as CFString
public let kCTFontCSSWidthAttribute = "CTFontCSSWidthAttribute" as CFString
public let kCTFontDescriptorTextStyleAttribute = "NSCTFontUIUsageAttribute" as CFString
public let kCTFontUIFontDesignTrait = "NSCTFontUIFontDesignTrait" as CFString

public let kCTFontPostScriptNameAttribute = "NSCTFontPostScriptNameAttribute" as CFString
public let kCTFontUserInstalledAttribute = "NSCTFontUserInstalledAttribute" as CFString
public let kCTFontFallbackOptionAttribute = "NSCTFontFallbackOptionAttribute" as CFString

public let kCTFontUIFontDesignDefault = "NSCTFontUIFontDesignDefault" as CFString
public let kCTFontUIFontDesignSerif = "NSCTFontUIFontDesignSerif" as CFString
public let kCTFontUIFontDesignMonospaced = "NSCTFontUIFontDesignMonospaced" as CFString
public let kCTFontUIFontDesignRounded = "NSCTFontUIFontDesignRounded" as CFString

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

public let kCTUIFontTextStyleShortHeadline = "UICTFontTextStyleShortHeadline" as CFString
public let kCTUIFontTextStyleShortBody = "UICTFontTextStyleShortBody" as CFString
public let kCTUIFontTextStyleShortSubhead = "UICTFontTextStyleShortSubhead" as CFString
public let kCTUIFontTextStyleShortFootnote = "UICTFontTextStyleShortFootnote" as CFString
public let kCTUIFontTextStyleShortCaption1 = "UICTFontTextStyleShortCaption1" as CFString
public let kCTUIFontTextStyleTallBody = "UICTFontTextStyleTallBody" as CFString

public let kCTUIFontTextStyleHeadline = "UICTFontTextStyleHeadline" as CFString
public let kCTUIFontTextStyleBody = "UICTFontTextStyleBody" as CFString
public let kCTUIFontTextStyleSubhead = "UICTFontTextStyleSubhead" as CFString
public let kCTUIFontTextStyleFootnote = "UICTFontTextStyleFootnote" as CFString
public let kCTUIFontTextStyleCaption1 = "UICTFontTextStyleCaption1" as CFString
public let kCTUIFontTextStyleCaption2 = "UICTFontTextStyleCaption2" as CFString

public let kCTUIFontTextStyleTitle0 = "UICTFontTextStyleTitle0" as CFString
public let kCTUIFontTextStyleTitle1 = "UICTFontTextStyleTitle1" as CFString
public let kCTUIFontTextStyleTitle2 = "UICTFontTextStyleTitle2" as CFString
public let kCTUIFontTextStyleTitle3 = "UICTFontTextStyleTitle3" as CFString
public let kCTUIFontTextStyleTitle4 = "UICTFontTextStyleTitle4" as CFString

public let kCTFontCSSFamilySerif = "serif" as CFString
public let kCTFontCSSFamilySansSerif = "sans-serif" as CFString
public let kCTFontCSSFamilyCursive = "cursive" as CFString
public let kCTFontCSSFamilyFantasy = "fantasy" as CFString
public let kCTFontCSSFamilyMonospace = "monospace" as CFString
public let kCTFontCSSFamilySystemUI = "system-ui" as CFString

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
