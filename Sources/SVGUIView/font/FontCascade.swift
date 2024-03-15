class FontCascade {
    var fontDescription: FontCascadeDescription
    var fonts: FontCascadeFonts?
    var generation: Int

    init(fontDescription: FontCascadeDescription = FontCascadeDescription(), fonts: FontCascadeFonts? = nil, generation: Int = 0) {
        self.fontDescription = fontDescription
        self.fonts = fonts
        self.generation = generation
    }

    func primaryFont() -> Font {
        fonts!.primaryFont(description: fontDescription)
    }

    static func isCJKIdeograph(_ c: UInt32) -> Bool {
        // The basic CJK Unified Ideographs block.
        if c >= 0x4E00, c <= 0x9FFF {
            return true
        }

        // CJK Unified Ideographs Extension A.
        if c >= 0x3400, c <= 0x4DBF {
            return true
        }

        // CJK Radicals Supplement.
        if c >= 0x2E80, c <= 0x2EFF {
            return true
        }

        // Kangxi Radicals.
        if c >= 0x2F00, c <= 0x2FDF {
            return true
        }

        // CJK Strokes.
        if c >= 0x31C0, c <= 0x31EF {
            return true
        }

        // CJK Compatibility Ideographs.
        if c >= 0xF900, c <= 0xFAFF {
            return true
        }

        // CJK Unified Ideographs Extension B.
        if c >= 0x20000, c <= 0x2A6DF {
            return true
        }

        // CJK Unified Ideographs Extension C.
        if c >= 0x2A700, c <= 0x2B73F {
            return true
        }

        // CJK Unified Ideographs Extension D.
        if c >= 0x2B740, c <= 0x2B81F {
            return true
        }

        // CJK Compatibility Ideographs Supplement.
        if c >= 0x2F800, c <= 0x2FA1F {
            return true
        }
        return false
    }
}
