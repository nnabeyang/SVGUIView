import CoreGraphics
import CoreText
import Foundation
import UIKit

struct SVGUIFont {
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
    }

    let name: String?
    let size: CGFloat?
    let weight: Weight?
    init(name: String?, size: CGFloat?, weight: String?) {
        self.name = name
        self.size = size
        self.weight = Weight(rawValue: weight ?? "")
    }

    init(lhs: SVGUIFont, rhs: SVGUIFont?) {
        guard let rhs = rhs else {
            self = lhs
            return
        }
        name = lhs.name ?? rhs.name
        size = lhs.size ?? rhs.size
        weight = lhs.weight ?? rhs.weight
    }

    init(child: SVGUIFont, parent: SVGUIFont?) {
        guard let parent = parent else {
            self = child
            return
        }
        name = child.name ?? parent.name
        size = child.size ?? parent.size
        weight = switch child.weight {
        case .normal:
            .normal
        case .bold:
            .bold
        case .lighter: {
                switch parent.weight {
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
        case .bolder: {
                switch parent.weight {
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
            .number(value)
        case .none:
            parent.weight
        }
    }

    var toCTFont: CTFont {
        var name = name ?? SVGUIView.familyNamesData[.standard]
        let families = name.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFontFamilies()
        }
        let size = size ?? 12.0
        let weight = weight ?? .normal
        let fontSelector = CSSFontSelector()
        let description = FontCascadeDescription()
        description.setFamilies(familyNames: families)
        description.computedSize = size
        description.fontSelectionRequest = FontSelectionRequest(
            weight: weight.value,
            width: .normalStretchValue
        )
        let fontCascade = FontCascade(fontDescription: description, fonts: FontCascadeFonts(fontSelector: fontSelector))
        return fontCascade.primaryFont().ctFont
    }
}
