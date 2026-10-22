import CoreFoundation
import CoreText

var kCTFontCSSWeightAttribute: CFString { "CTFontCSSWeightAttribute" as CFString }
var kCTFontCSSWidthAttribute: CFString { "CTFontCSSWidthAttribute" as CFString }
var kCTFontDescriptorTextStyleAttribute: CFString { "NSCTFontUIUsageAttribute" as CFString }
var kCTFontUIFontDesignTrait: CFString { "NSCTFontUIFontDesignTrait" as CFString }

var kCTFontPostScriptNameAttribute: CFString { "NSCTFontPostScriptNameAttribute" as CFString }
var kCTFontUserInstalledAttribute: CFString { "NSCTFontUserInstalledAttribute" as CFString }
var kCTFontFallbackOptionAttribute: CFString { "NSCTFontFallbackOptionAttribute" as CFString }

var kCTFontUIFontDesignDefault: CFString { "NSCTFontUIFontDesignDefault" as CFString }
var kCTFontUIFontDesignSerif: CFString { "NSCTFontUIFontDesignSerif" as CFString }
var kCTFontUIFontDesignMonospaced: CFString { "NSCTFontUIFontDesignMonospaced" as CFString }
var kCTFontUIFontDesignRounded: CFString { "NSCTFontUIFontDesignRounded" as CFString }

let kCTFontWidthUltraCompressed: CGFloat = -0.5
let kCTFontWidthExtraCompressed: CGFloat = -0.4
let kCTFontWidthCompressed: CGFloat = -0.3
let kCTFontWidthExtraCondensed: CGFloat = -0.3
let kCTFontWidthCondensed: CGFloat = -0.2
let kCTFontWidthSemiCondensed: CGFloat = -0.1
let kCTFontWidthStandard: CGFloat = 0.0
let kCTFontWidthSemiExpanded: CGFloat = 0.1
let kCTFontWidthExpanded: CGFloat = 0.2
let kCTFontWidthExtraExpanded: CGFloat = 0.3

var kCTUIFontTextStyleShortHeadline: CFString { "UICTFontTextStyleShortHeadline" as CFString }
var kCTUIFontTextStyleShortBody: CFString { "UICTFontTextStyleShortBody" as CFString }
var kCTUIFontTextStyleShortSubhead: CFString { "UICTFontTextStyleShortSubhead" as CFString }
var kCTUIFontTextStyleShortFootnote: CFString { "UICTFontTextStyleShortFootnote" as CFString }
var kCTUIFontTextStyleShortCaption1: CFString { "UICTFontTextStyleShortCaption1" as CFString }
var kCTUIFontTextStyleTallBody: CFString { "UICTFontTextStyleTallBody" as CFString }

var kCTUIFontTextStyleHeadline: CFString { "UICTFontTextStyleHeadline" as CFString }
var kCTUIFontTextStyleBody: CFString { "UICTFontTextStyleBody" as CFString }
var kCTUIFontTextStyleSubhead: CFString { "UICTFontTextStyleSubhead" as CFString }
var kCTUIFontTextStyleFootnote: CFString { "UICTFontTextStyleFootnote" as CFString }
var kCTUIFontTextStyleCaption1: CFString { "UICTFontTextStyleCaption1" as CFString }
var kCTUIFontTextStyleCaption2: CFString { "UICTFontTextStyleCaption2" as CFString }

var kCTUIFontTextStyleTitle0: CFString { "UICTFontTextStyleTitle0" as CFString }
var kCTUIFontTextStyleTitle1: CFString { "UICTFontTextStyleTitle1" as CFString }
var kCTUIFontTextStyleTitle2: CFString { "UICTFontTextStyleTitle2" as CFString }
var kCTUIFontTextStyleTitle3: CFString { "UICTFontTextStyleTitle3" as CFString }
var kCTUIFontTextStyleTitle4: CFString { "UICTFontTextStyleTitle4" as CFString }

var kCTFontCSSFamilySerif: CFString { "serif" as CFString }
var kCTFontCSSFamilySansSerif: CFString { "sans-serif" as CFString }
var kCTFontCSSFamilyCursive: CFString { "cursive" as CFString }
var kCTFontCSSFamilyFantasy: CFString { "fantasy" as CFString }
var kCTFontCSSFamilyMonospace: CFString { "monospace" as CFString }
var kCTFontCSSFamilySystemUI: CFString { "system-ui" as CFString }

func CTFontCreateLastResort(_ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
  CTFontCreateWithName("LastResort" as CFString, size, matrix)
}

func CTFontIsAppleColorEmoji(_ font: CTFont) -> Bool {
  CTFontCopyFullName(font) as String == "Apple Color Emoji"
}

func CTFontDescriptorIsSystemUIFont(_ descriptor: CTFontDescriptor) -> Bool {
  switch CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
  case ".AppleSystemUIFont", ".AppleSystemUIFontMonospaced":
    return true
  default:
    return false
  }
}
