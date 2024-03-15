import _SPI
import UIKit

class SystemFontDatabaseCoreText {
    var serifFamilies = [String: String]()
    var sansSerifFamilies = [String: String]()
    var cursiveFamilies = [String: String]()
    var monospaceFamilies = [String: String]()
    var fantasyFamilies = [String: String]()
    var systemFontCache = [CascadeListParameters: [CTFontDescriptor]]()
    var textStyles = [CFString]()

    static var shared: SystemFontDatabaseCoreText {
        FontCache.shared.systemFontDatabaseCoreText
    }

    struct CascadeListParameters: Hashable {
        var fontName: String = ""
        var locale: String? = nil
        var weight: CGFloat = 0
        var width: CGFloat = 0
        var size: Double = 0
        var allowUserInstalledFonts = AllowUserInstalledFonts.no
        var italic = false

        init() {}
    }

    func cascadeList(parameters: CascadeListParameters, systemFontKind: SystemFontKind) -> [CTFontDescriptor] {
        let locale = parameters.locale as CFString?
        let systemFont: CTFont?
        switch systemFontKind {
        case .systemUI:
            systemFont = Self.createSystemUIFont(parameters: parameters, locale: locale)
        case .uiSerif, .uiMonospace, .uiRounded:
            systemFont = Self.createSystemDesignFont(systemFontKind: systemFontKind, parameters: parameters)
        case .textStyle:
            systemFont = Self.createTextStyleFont(parameters: parameters)
        }
        let result = computeCascadeList(font: systemFont!, locale: locale)
        systemFontCache[parameters] = result
        return result
    }

    func cascadeList(description: FontDescription, cssFamily: String, systemFontKind: SystemFontKind, allowUserInstalledFonts: AllowUserInstalledFonts) -> [CTFontDescriptor] {
        let parameters = systemFontParameters(description: description, familyName: cssFamily, systemFontKind: systemFontKind, allowUserInstalledFonts: allowUserInstalledFonts)
        return cascadeList(parameters: parameters, systemFontKind: systemFontKind)
    }

    func computeCascadeList(font: CTFont, locale: CFString?) -> [CTFontDescriptor] {
        let localeArray = locale.flatMap { [$0] as CFArray }
        let cascadeList = CTFontCopyDefaultCascadeListForLanguages(font, localeArray)
        var result = [CTFontDescriptor]()
        let fontDescriptor = CTFontCopyFontDescriptor(font)
        result.append(removeCascadeList(fontDescriptor: fontDescriptor))
        if let cascadeList = cascadeList {
            let n = CFArrayGetCount(cascadeList)
            for i in 0 ..< n {
                result.append(unsafeBitCast(CFArrayGetValueAtIndex(cascadeList, i), to: CTFontDescriptor.self))
            }
        }
        return result
    }

    func removeCascadeList(fontDescriptor: CTFontDescriptor) -> CTFontDescriptor {
        var attributes = [CFString: Any]()
        attributes[kCTFontCascadeListAttribute] = [Any]() as CFArray
        return CTFontDescriptorCreateCopyWithAttributes(fontDescriptor, attributes as CFDictionary)
    }

    static func createSystemUIFont(parameters: CascadeListParameters, locale: CFString?) -> CTFont? {
        let result = CTFontCreateUIFontForLanguage(CTFontUIFontType.system, parameters.size, locale)
        return Self.createFontByApplyingWeightWidthItalicsAndFallbackBehavior(font: result,
                                                                              weight: parameters.weight,
                                                                              width: parameters.width,
                                                                              italic: parameters.italic,
                                                                              size: parameters.size,
                                                                              allowUserInstalledFonts: parameters.allowUserInstalledFonts)
    }

    static func createSystemDesignFont(systemFontKind: SystemFontKind, parameters: CascadeListParameters) -> CTFont? {
        let design: CFString
        switch systemFontKind {
        case .uiSerif:
            design = kCTFontUIFontDesignSerif
        case .uiMonospace:
            design = kCTFontUIFontDesignMonospaced
        case .uiRounded:
            design = kCTFontUIFontDesignRounded
        case .systemUI, .textStyle:
            fatalError("no reach")
        }
        return Self.createFontByApplyingWeightWidthItalicsAndFallbackBehavior(font: nil,
                                                                              weight: parameters.weight,
                                                                              width: parameters.width,
                                                                              italic: parameters.italic,
                                                                              size: parameters.size,
                                                                              allowUserInstalledFonts: parameters.allowUserInstalledFonts,
                                                                              design: design)
    }

    static func createTextStyleFont(parameters: CascadeListParameters) -> CTFont? {
        let locale = parameters.locale.flatMap { $0 as CFString }
        guard var descriptor = CTFontDescriptorCreateWithTextStyle(parameters.fontName as CFString, Self.contentSizeCategory, locale)?.takeRetainedValue() else { return nil }

        let traits: CTFontSymbolicTraits = [
            parameters.weight >= UIFont.Weight.semibold.rawValue ? .boldTrait : .zero,
            parameters.width >= kCTFontWidthSemiExpanded ? .expandedTrait : .zero,
            parameters.width <= kCTFontWidthSemiCondensed ? .condensedTrait : .zero,
            parameters.italic ? .italicTrait : .zero,
        ]
        if traits != .zero,
           let modified = CTFontDescriptorCreateCopyWithSymbolicTraits(descriptor, traits, traits)
        {
            descriptor = modified
        }
        return CTFontCreateWithFontDescriptor(descriptor, parameters.size, nil)
    }

    static func createFontForInstalledFonts(fontDescriptor: CTFontDescriptor, size: CGFloat, allowUserInstalledFonts: AllowUserInstalledFonts) -> CTFont? {
        var attributes = [CFString: Any]()
        Self.addAttributesForInstalledFonts(attributes: &attributes, allowUserInstalledFonts: allowUserInstalledFonts)
        guard !attributes.isEmpty else {
            return CTFontCreateWithFontDescriptor(fontDescriptor, size, nil)
        }
        let resultFontDescriptor = CTFontDescriptorCreateCopyWithAttributes(fontDescriptor, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(resultFontDescriptor, size, nil)
    }

    static var contentSizeCategory: CFString = UIApplication.shared.preferredContentSizeCategory.rawValue as CFString

    static func createFontByApplyingWeightWidthItalicsAndFallbackBehavior(font: CTFont?, weight: CGFloat, width: CGFloat, italic: Bool, size: Double,
                                                                          allowUserInstalledFonts: AllowUserInstalledFonts, design: CFString? = nil) -> CTFont?
    {
        let weightNumber = weight as CFNumber
        let widthNumber = width as CFNumber
        let italicsNumber = (italic ? 0.07 : 0.0) as CFNumber
        var traits = [CFString: Any]()
        traits[kCTFontWeightTrait] = weightNumber
        traits[kCTFontWidthTrait] = widthNumber
        traits[kCTFontSlantTrait] = italicsNumber
        traits[kCTFontUIFontDesignTrait] = design ?? kCTFontUIFontDesignDefault

        var attributes = [CFString: Any]()
        attributes[kCTFontTraitsAttribute] = traits
        Self.addAttributesForInstalledFonts(attributes: &attributes, allowUserInstalledFonts: allowUserInstalledFonts)
        let modification = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        if let font = font {
            return CTFontCreateCopyWithAttributes(font, size, nil, modification)
        }
        return CTFontCreateWithFontDescriptor(modification, size, nil)
    }

    static func addAttributesForInstalledFonts(attributes: inout [CFString: Any], allowUserInstalledFonts: AllowUserInstalledFonts) {
        guard allowUserInstalledFonts == .no else { return }
        attributes[kCTFontUserInstalledAttribute] = kCFBooleanFalse
        attributes[kCTFontFallbackOptionAttribute] = CTFontFallbackOption.system.rawValue as CFNumber
    }

    func systemFontParameters(description: FontDescription, familyName: String,
                              systemFontKind: SystemFontKind, allowUserInstalledFonts: AllowUserInstalledFonts) -> CascadeListParameters
    {
        var result = CascadeListParameters()
        result.locale = description.locale
        result.size = description.computedSize
        result.italic = FontSelectionValue.isItalic(slope: description.italic)
        result.allowUserInstalledFonts = allowUserInstalledFonts

        result.weight = Self.mapWeight(weight: description.weight)
        result.width = Self.mapWidth(width: description.stretch)

        switch systemFontKind {
        case .systemUI:
            result.fontName = "system-ui"
        case .uiSerif:
            result.fontName = "ui-serif"
        case .uiMonospace:
            result.fontName = "ui-monospace"
        case .uiRounded:
            result.fontName = "ui-rounded"
        case .textStyle:
            result.fontName = familyName
        }
        return result
    }

    private static let compareAsPointer: ((CFString, CFString) -> Bool) = { (lhs: CFString, rhs: CFString) in
        let result = CFStringCompare(lhs, rhs, CFStringCompareFlags(rawValue: 0))
        switch result {
        case .compareEqualTo, .compareLessThan: return true
        case .compareGreaterThan: return false
        @unknown default: return false
        }
    }

    func matchSystemFontUse(string: String) -> SystemFontKind? {
        if SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "-webkit-system-font")
            || SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "-apple-system")
            || SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "-apple-system-font")
            || SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "system-ui")
            || SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "ui-sans-serif")
        {
            return .systemUI
        }
        if SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "ui-serif") {
            return .uiSerif
        }
        if SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "ui-monospace") {
            return .uiMonospace
        }
        if SVGUIView.equalLettersIgnoringASCIICase(string: string, literal: "ui-rounded") {
            return .uiRounded
        }
        if textStyles.isEmpty {
            textStyles = [
                kCTUIFontTextStyleHeadline,
                kCTUIFontTextStyleBody,
                kCTUIFontTextStyleTitle1,
                kCTUIFontTextStyleTitle2,
                kCTUIFontTextStyleTitle3,
                kCTUIFontTextStyleSubhead,
                kCTUIFontTextStyleFootnote,
                kCTUIFontTextStyleCaption1,
                kCTUIFontTextStyleCaption2,
                kCTUIFontTextStyleShortHeadline,
                kCTUIFontTextStyleShortBody,
                kCTUIFontTextStyleShortSubhead,
                kCTUIFontTextStyleShortFootnote,
                kCTUIFontTextStyleShortCaption1,
                kCTUIFontTextStyleTallBody,
                kCTUIFontTextStyleTitle0,
                kCTUIFontTextStyleTitle4,
            ]
            textStyles.sort(by: Self.compareAsPointer)
        }
        let index = textStyles.partitioningIndex(where: { $0 == (string as CFString) })
        if index < textStyles.count {
            return .textStyle
        }
        return nil
    }

    static func mapWeight(weight: FontSelectionValue) -> CGFloat {
        if weight < FontSelectionValue(150) { return UIFont.Weight.ultraLight.rawValue }
        if weight < FontSelectionValue(250) { return UIFont.Weight.thin.rawValue }
        if weight < FontSelectionValue(350) { return UIFont.Weight.light.rawValue }
        if weight < FontSelectionValue(450) { return UIFont.Weight.regular.rawValue }
        if weight < FontSelectionValue(550) { return UIFont.Weight.medium.rawValue }
        if weight < FontSelectionValue(650) { return UIFont.Weight.semibold.rawValue }
        if weight < FontSelectionValue(750) { return UIFont.Weight.bold.rawValue }
        if weight < FontSelectionValue(850) { return UIFont.Weight.heavy.rawValue }
        return UIFont.Weight.black.rawValue
    }

    static let piecewisePoints: [(input: FontSelectionValue, output: CGFloat)] = [
        (FontSelectionValue(backing: 150), kCTFontWidthUltraCompressed),
        (FontSelectionValue(backing: 200), kCTFontWidthExtraCompressed),
        (FontSelectionValue(backing: 250), kCTFontWidthExtraCondensed),
        (FontSelectionValue(backing: 300), kCTFontWidthCondensed),
        (FontSelectionValue(backing: 350), kCTFontWidthSemiCondensed),
        (FontSelectionValue(backing: 400), kCTFontWidthStandard),
        (FontSelectionValue(backing: 450), kCTFontWidthSemiExpanded),
        (FontSelectionValue(backing: 500), kCTFontWidthExpanded),
        (FontSelectionValue(backing: 600), kCTFontWidthExtraExpanded),
    ]

    static func mapWidth(width: FontSelectionValue) -> CGFloat {
        let n = Self.piecewisePoints.count - 1
        for i in 0 ..< n {
            let previous = Self.piecewisePoints[i]
            let next = Self.piecewisePoints[i + 1]
            let middleInput = (previous.input + next.input).double / 2.0
            if width.double < middleInput { return previous.output }
        }
        return Self.piecewisePoints[n].output
    }

    static func genericFamily(locale: String, map: inout [String: String], ctKey: CFString) -> String? {
        if let name = map[locale] {
            return name
        }
        let descriptor = CTFontDescriptorCreateForCSSFamily(ctKey, locale as CFString).takeRetainedValue()
        guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String else {
            return nil
        }
        map[locale] = name
        return name
    }

    func serifFamily(locale: String) -> String? {
        Self.genericFamily(locale: locale, map: &serifFamilies, ctKey: kCTFontCSSFamilySerif)
    }

    func sansSerifFamily(locale: String) -> String? {
        Self.genericFamily(locale: locale, map: &sansSerifFamilies, ctKey: kCTFontCSSFamilySansSerif)
    }

    func cursiveFamily(locale: String) -> String? {
        Self.genericFamily(locale: locale, map: &cursiveFamilies, ctKey: kCTFontCSSFamilyCursive)
    }

    func fantasyFamily(locale: String) -> String? {
        Self.genericFamily(locale: locale, map: &fantasyFamilies, ctKey: kCTFontCSSFamilyFantasy)
    }

    func monospaceFamily(locale: String) -> String? {
        Self.genericFamily(locale: locale, map: &monospaceFamilies, ctKey: kCTFontCSSFamilyMonospace)
    }
}

extension CTFontSymbolicTraits {
    static let zero = CTFontSymbolicTraits([])
}

extension Collection {
    func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Index {
        var n = count
        var l = startIndex

        while n > 0 {
            let half = n / 2
            let mid = index(l, offsetBy: half)
            if belongsInSecondPartition(self[mid]) {
                n = half
            } else {
                l = index(after: mid)
                n -= half + 1
            }
        }
        return l
    }
}
