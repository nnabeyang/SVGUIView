#pragma once

#include <CoreText/CoreText.h>

typedef CF_OPTIONS(CFOptionFlags, CTFontFallbackOption) {
    kCTFontFallbackOptionNone = 0,
    kCTFontFallbackOptionSystem = 1 << 0,
    kCTFontFallbackOptionUserInstalled = 1 << 1,
    kCTFontFallbackOptionDefault = kCTFontFallbackOptionSystem | kCTFontFallbackOptionUserInstalled,
};

typedef CF_OPTIONS(uint32_t, CTFontDescriptorOptions) {
    kCTFontDescriptorOptionSystemUIFont = 1 << 1,
    kCTFontDescriptorOptionPreferAppleSystemFont = kCTFontOptionsPreferSystemFont
};

bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef);

extern const CFStringRef kCTFontCSSWeightAttribute;
extern const CFStringRef kCTFontCSSWidthAttribute;
extern const CFStringRef kCTFontDescriptorTextStyleAttribute;
extern const CFStringRef kCTFontUIFontDesignTrait;

extern const CFStringRef kCTFontPostScriptNameAttribute;
extern const CFStringRef kCTFontUserInstalledAttribute;
extern const CFStringRef kCTFontFallbackOptionAttribute;

CTFontDescriptorRef CTFontDescriptorCreateWithTextStyle(CFStringRef style, CFStringRef size, CFStringRef language);
CTFontDescriptorRef CTFontDescriptorCreateForCSSFamily(CFStringRef cssFamily, CFStringRef language);
CTFontRef CTFontCreateForCharactersWithLanguage(CTFontRef currentFont, const UTF16Char *characters, CFIndex length, CFStringRef language, CFIndex *coveredLength);

extern const CFStringRef kCTFontUIFontDesignDefault;
extern const CFStringRef kCTFontUIFontDesignSerif;
extern const CFStringRef kCTFontUIFontDesignMonospaced;
extern const CFStringRef kCTFontUIFontDesignRounded;

extern const CGFloat kCTFontWidthUltraCompressed;
extern const CGFloat kCTFontWidthExtraCompressed;
extern const CGFloat kCTFontWidthCompressed;
extern const CGFloat kCTFontWidthExtraCondensed;
extern const CGFloat kCTFontWidthCondensed;
extern const CGFloat kCTFontWidthSemiCondensed;
extern const CGFloat kCTFontWidthStandard;
extern const CGFloat kCTFontWidthSemiExpanded;
extern const CGFloat kCTFontWidthExpanded;
extern const CGFloat kCTFontWidthExtraExpanded;

extern const CFStringRef kCTUIFontTextStyleShortHeadline;
extern const CFStringRef kCTUIFontTextStyleShortBody;
extern const CFStringRef kCTUIFontTextStyleShortSubhead;
extern const CFStringRef kCTUIFontTextStyleShortFootnote;
extern const CFStringRef kCTUIFontTextStyleShortCaption1;
extern const CFStringRef kCTUIFontTextStyleTallBody;

extern const CFStringRef kCTUIFontTextStyleHeadline;
extern const CFStringRef kCTUIFontTextStyleBody;
extern const CFStringRef kCTUIFontTextStyleSubhead;
extern const CFStringRef kCTUIFontTextStyleFootnote;
extern const CFStringRef kCTUIFontTextStyleCaption1;
extern const CFStringRef kCTUIFontTextStyleCaption2;

extern const CFStringRef kCTUIFontTextStyleTitle0;
extern const CFStringRef kCTUIFontTextStyleTitle1;
extern const CFStringRef kCTUIFontTextStyleTitle2;
extern const CFStringRef kCTUIFontTextStyleTitle3;
extern const CFStringRef kCTUIFontTextStyleTitle4;

extern const CFStringRef kCTFontCSSFamilySerif;
extern const CFStringRef kCTFontCSSFamilySansSerif;
extern const CFStringRef kCTFontCSSFamilyCursive;
extern const CFStringRef kCTFontCSSFamilyFantasy;
extern const CFStringRef kCTFontCSSFamilyMonospace;
extern const CFStringRef kCTFontCSSFamilySystemUI;

bool CTFontIsAppleColorEmoji(CTFontRef);
CTFontSymbolicTraits CTFontGetPhysicalSymbolicTraits(CTFontRef);

CTFontDescriptorRef CTFontDescriptorCreateLastResort();
bool CTFontGetVerticalGlyphsForCharacters(CTFontRef, const UniChar characters[], CGGlyph glyphs[], CFIndex count);
