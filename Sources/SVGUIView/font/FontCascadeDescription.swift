class FontCascadeDescription: FontDescription {
    var familyNames: [String] = []
    func setFamilies(familyNames: [String]) {
        self.familyNames = familyNames
    }

    var useFixedDefaultSize: Bool {
        familyNames.count == 1 && familyNames[0] == SVGUIView.familyNamesData[.monospace]
    }

    var effectiveFamilyCount: Int {
        var result = 0
        for familyName in familyNames {
            if let use = SystemFontDatabaseCoreText.shared.matchSystemFontUse(string: familyName) {
                let cascadeList = SVGUIView.systemFontCascadeList(description: self, cssFamily: familyName,
                                                                  systemFontKind: use, allowUserInstalledFonts: shouldAllowUserInstalledFonts)

                result += cascadeList.count
            } else {
                result += 1
            }
        }
        return result
    }

    func effectiveFamilyAt(index: Int) -> FontFamilySpecification {
        var index = index
        for familyName in familyNames {
            if let use = SystemFontDatabaseCoreText.shared.matchSystemFontUse(string: familyName) {
                let cascadeList = SVGUIView.systemFontCascadeList(description: self, cssFamily: familyName,
                                                                  systemFontKind: use, allowUserInstalledFonts: shouldAllowUserInstalledFonts)
                if index < cascadeList.count {
                    return .spec(FontFamilySpecificationCoreText(fontDescriptor: cascadeList[index]))
                }
                index -= cascadeList.count
            } else if index == 0 {
                return .string(familyName)
            } else {
                index -= 1
            }
        }
        fatalError("no reach")
    }

    static func foldedFamilyName(_ name: String) -> String {
        if name.hasPrefix(".") { return name }
        return name.lowercased()
    }

    static var initialFontStyleAxis: FontStyleAxis { .slnt }
    static var initialItalic: FontSelectionValue? { nil }
    static var initialWeight: FontSelectionValue { FontSelectionValue.normalWeightValue }
    static var initialStretch: FontSelectionValue { FontSelectionValue.normalStretchValue }
}

enum FontStyleAxis: UInt8 {
    case slnt
    case ital
}

struct FontDescriptionKey {
    var isDeletedValue: Bool
    var size: Double
    var fontSelectionRequest: FontSelectionRequest
    var locale: String
    var flags: (UInt, UInt)
    init() {
        isDeletedValue = false
        size = 0
        fontSelectionRequest = FontSelectionRequest()
        locale = ""
        flags = (0, 0)
    }

    init(description: FontDescription) {
        isDeletedValue = false
        size = description.computedSize
        fontSelectionRequest = description.fontSelectionRequest
        locale = description.specifiedLocale
        flags = (0, 0)
    }
}

extension FontDescriptionKey: Hashable {
    static func == (lhs: FontDescriptionKey, rhs: FontDescriptionKey) -> Bool {
        lhs.isDeletedValue == rhs.isDeletedValue
            && lhs.size == rhs.size
            && lhs.fontSelectionRequest == rhs.fontSelectionRequest
            && lhs.flags.0 == rhs.flags.0
            && lhs.flags.1 == rhs.flags.1
            && lhs.locale == rhs.locale
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        hasher.combine(fontSelectionRequest)
        hasher.combine(flags.0)
        hasher.combine(flags.1)
        hasher.combine(locale)
    }
}

enum FontFamilySpecification {
    case string(String?)
    case spec(FontFamilySpecificationCoreText)
}
