#pragma once

#include <CoreFoundation/CFBase.h>

typedef CF_OPTIONS(CFOptionFlags, CTFontFallbackOption) {
    kCTFontFallbackOptionNone = 0,
    kCTFontFallbackOptionSystem = 1 << 0,
    kCTFontFallbackOptionUserInstalled = 1 << 1,
    kCTFontFallbackOptionDefault = kCTFontFallbackOptionSystem | kCTFontFallbackOptionUserInstalled,
};

typedef CF_OPTIONS(uint32_t, CTFontDescriptorOptions) {
    kCTFontDescriptorOptionSystemUIFont = 1 << 1,
    kCTFontDescriptorOptionPreferAppleSystemFont = 1 << 2
};
