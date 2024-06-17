import CoreGraphics
import CoreText
import Foundation
import UIKit

struct SVGUIFont {
    let name: String?
    let size: Size?
    let weight: Weight?
    let fontDescription: FontCascadeDescription

    init(name: String?, size: String?, weight: String?) {
        self.name = name
        self.size = size.flatMap { Size(rawValue: $0) }
        self.weight = Weight(rawValue: weight ?? "")
        var name = name ?? SVGUIView.familyNamesData[.standard]
        let families = name.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFontFamilies()
        }
        fontDescription = FontCascadeDescription()
        fontDescription.setFamilies(familyNames: families)
        fontDescription.setSpecifiedLocale(locale: Locale.current.identifier)
    }

    init(name: String?, weight: Weight?) {
        self.name = name
        size = nil
        self.weight = weight
        var name = name ?? SVGUIView.familyNamesData[.standard]
        let families = name.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFontFamilies()
        }
        fontDescription = FontCascadeDescription()
        fontDescription.setFamilies(familyNames: families)
    }

    init(lhs: SVGUIFont, rhs: SVGUIFont?) {
        guard let rhs = rhs else {
            self = lhs
            return
        }
        name = lhs.name ?? rhs.name
        size = lhs.size ?? rhs.size
        weight = lhs.weight ?? rhs.weight
        var name = name ?? SVGUIView.familyNamesData[.standard]
        let families = name.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFontFamilies()
        }
        fontDescription = FontCascadeDescription()
        fontDescription.setFamilies(familyNames: families)
    }

    init(child: SVGUIFont, context: SVGContext) {
        guard let parent = context.font else {
            self = child
            return
        }
        name = child.name ?? parent.name
        size = Size(child: child.size, context: context)
        weight = Weight(child: child.weight, parent: parent.weight)
        var name = name ?? SVGUIView.familyNamesData[.standard]
        let families = name.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFontFamilies()
        }
        fontDescription = FontCascadeDescription()
        fontDescription.setFamilies(familyNames: families)
    }

    func sizeValue(context: SVGLengthContext, textScale: Double = 1.0) -> CGFloat {
        let size = size ?? .medium
        return size.value(context: context, shouldUseFixedDefaultSize: fontDescription.useFixedDefaultSize) * textScale
    }

    func fontCascade(textScale: Double, context: SVGLengthContext) -> FontCascade {
        Self.createFontCascade(size: size, weight: weight, fontDescription: fontDescription, textScale: textScale, context: context)
    }

    static func createFontCascade(size: Size?, weight: Weight?, fontDescription: FontCascadeDescription,
                                  textScale: Double, context: SVGLengthContext) -> FontCascade
    {
        let weight = weight ?? .normal
        let fontSelector = CSSFontSelector()
        let size = size ?? .medium
        let computedSize = size.value(context: context, shouldUseFixedDefaultSize: fontDescription.useFixedDefaultSize) * textScale

        fontDescription.computedSize = computedSize
        fontDescription.fontSelectionRequest = FontSelectionRequest(
            weight: weight.value,
            width: .normalStretchValue
        )
        return FontCascade(fontDescription: fontDescription, fonts: FontCascadeFonts(fontSelector: fontSelector))
    }

    func ctFont(context: SVGLengthContext, textScale: Double = 1.0) -> CTFont {
        let font = fontCascade(textScale: textScale, context: context).primaryFont()
        return font.ctFont
    }
}

extension SVGUIFont {
    enum Weight: RawRepresentable {
        typealias RawValue = String
        case normal
        case bold
        case lighter
        case bolder
        case number(Double)

        init?(rawValue: String) {
            switch rawValue {
            case "normal":
                self = .normal
            case "bold":
                self = .bold
            case "lighter":
                self = .lighter
            case "bolder":
                self = .bolder
            default:
                guard let value = Double(rawValue), value <= 1000 else {
                    return nil
                }
                self = .number(value)
            }
        }

        var rawValue: String {
            switch self {
            case .normal: return "normal"
            case .lighter: return "lighter"
            case .bold: return "bold"
            case .bolder: return "bolder"
            case .number: return "number"
            }
        }

        var value: FontSelectionValue {
            switch self {
            case .normal: return .init(400)
            case .lighter: return .init(100)
            case .bold, .bolder: return .init(700)
            case let .number(value): return .init(value)
            }
        }

        init?(child: Weight?, parent: Weight?) {
            switch child {
            case .normal:
                self = .normal
            case .bold:
                self = .bold
            case .lighter:
                self = {
                    switch parent {
                    case .normal, .bold, .lighter, .bolder:
                        return .number(100)
                    case let .number(value):
                        if value <= 500 {
                            return .number(100)
                        }
                        if value <= 700 {
                            return .normal
                        }
                        return .bold
                    case .none:
                        return .lighter
                    }
                }()
            case .bolder:
                self = {
                    switch parent {
                    case .lighter:
                        return .normal
                    case .normal:
                        return .bold
                    case .bold, .bolder:
                        return .number(900)
                    case let .number(value):
                        if value <= 300 {
                            return .normal
                        }
                        if value <= 500 {
                            return .bold
                        }
                        return .number(900)
                    case .none:
                        return .bold
                    }
                }()
            case let .number(value):
                self = .number(value)
            case .none:
                guard let parent = parent else { return nil }
                self = parent
            }
        }
    }

    enum Size: RawRepresentable {
        static var defaultFixedFontSize: CGFloat { 13 }
        static var defaultFontSize: CGFloat { 16 }
        typealias RawValue = String

        case xxSmall
        case xSmall
        case small
        case medium
        case large
        case xLarge
        case xxLarge
        case xxxLarge
        case smaller
        case larger
        case length(SVGLength)

        init?(rawValue: String) {
            switch rawValue {
            case "xx-small":
                self = .xxSmall
            case "x-small":
                self = .xSmall
            case "small":
                self = .small
            case "medium":
                self = .medium
            case "large":
                self = .large
            case "x-large":
                self = .xLarge
            case "xx-large":
                self = .xxLarge
            case "xxx-large":
                self = .xxxLarge
            case "smaller":
                self = .smaller
            case "larger":
                self = .larger
            default:
                guard let value = SVGLength(rawValue) else {
                    return nil
                }
                self = .length(value)
            }
        }

        var rawValue: String {
            switch self {
            case .xxSmall: "xx-small"
            case .xSmall: "x-small"
            case .small: "small"
            case .medium: "medium"
            case .large: "large"
            case .xLarge: "x-large"
            case .xxLarge: "xx-large"
            case .xxxLarge: "xxx-large"
            case .smaller: "smaller"
            case .larger: "larger"
            case let .length(value): value.description
            }
        }

        func value(context: SVGLengthContext, shouldUseFixedDefaultSize: Bool) -> CGFloat {
            switch self {
            case .xxSmall: 9
            case .xSmall: shouldUseFixedDefaultSize ? 9 : 10
            case .small: shouldUseFixedDefaultSize ? 10 : 13
            case .medium: shouldUseFixedDefaultSize ? Self.defaultFixedFontSize : Self.defaultFontSize
            case .large: shouldUseFixedDefaultSize ? 16 : 18
            case .xLarge: shouldUseFixedDefaultSize ? 20 : 24
            case .xxLarge: shouldUseFixedDefaultSize ? 26 : 32
            case .xxxLarge: shouldUseFixedDefaultSize ? 40 : 48
            case .smaller: fatalError()
            case .larger: fatalError()
            case let .length(length):
                length.fontValue(context: context)
            }
        }

        init?(child: Size?, context: SVGContext) {
            guard let parent = context.font else {
                guard let child = child else { return nil }
                self = child
                return
            }
            switch child {
            case .xxSmall, .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
                self = child!
            case .smaller:
                let size: CGFloat = context.font?.sizeValue(context: context, textScale: 1.0) ?? Self.defaultFontSize
                self = .length(.pixel(Self.smallerFontSize(size)))
            case .larger:
                let size: CGFloat = context.font?.sizeValue(context: context, textScale: 1.0) ?? Self.defaultFontSize
                self = .length(.pixel(Self.largerFontSize(size)))
            case let .length(length):
                let fontValue = length.fontValue(context: context)
                self = .length(.number(fontValue))
            case .none:
                guard let parentSize = parent.size else { return nil }
                self = parentSize
            }
        }

        private static func smallerFontSize(_ size: CGFloat) -> CGFloat {
            size / 1.2
        }

        private static func largerFontSize(_ size: CGFloat) -> CGFloat {
            size * 1.2
        }
    }
}

extension CTFont {
    static func standard(context: SVGLengthContext) -> CTFont {
        let name = SVGUIView.familyNamesData[.standard]
        let size: SVGUIFont.Size = .length(.pixel(SVGUIFont.Size.defaultFontSize))
        let fontDescription = FontCascadeDescription()
        fontDescription.setFamilies(familyNames: [name])
        let fontCascade = SVGUIFont.createFontCascade(size: size, weight: .normal, fontDescription: fontDescription, textScale: 1.0, context: context)
        return fontCascade.primaryFont().ctFont
    }
}
