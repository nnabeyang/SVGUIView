import SVGView
import UIKit

private enum FontType {
    case normal(String)
    case mono
    case system
}

extension SVGFont {
    private static let nameMap: [String: FontType] = [
        "Noto Sans": .normal("Times New Roman"),
        "system-ui": .system,
        "ui-monospace": .mono,
    ]

    func toCTFont() -> CTFont {
        var attributes: [CFString: Any] = [:]
        let familyName: FontType = {
            let fontNames = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for fontName in fontNames {
                if let modified = Self.nameMap[fontName] {
                    return modified
                }
            }
            return .normal(name)
        }()

        let descriptor: CTFontDescriptor = {
            switch familyName {
            case let .normal(value):
                attributes[kCTFontFamilyNameAttribute] = value as CFString
                attributes[kCTFontSizeAttribute] = NSNumber(value: size)
                return CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            case .system:
                let uiFont = UIFont.systemFont(ofSize: size)
                return uiFont.fontDescriptor as CTFontDescriptor
            case .mono:
                let uiFont = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
                return uiFont.fontDescriptor as CTFontDescriptor
            }
        }()
        return CTFontCreateWithFontDescriptor(descriptor, 0.0, nil)
    }
}
