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
}
