import CoreGraphics
import CoreText
import Foundation

/// A font with the computed values of `font-family`, `font-size` and `font-weight`.
struct SVGUIFont {
  let name: String
  let size: Size
  let weight: Weight
  /// The font families, in order of preference.
  let families: [String]
  /// The locale for choosing fonts, such as the fonts for Han characters, or `nil` for none.
  let specifiedLocale: String?

  init(name: String, size: Size, weight: Weight) {
    self.name = name
    self.size = size
    self.weight = weight
    var name = name
    let families = name.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanFontFamilies()
    }
    self.families = families
    specifiedLocale = Locale.current.identifier
  }

  func sizeValue(context: any SVGLengthContext, textScale: Double = 1.0) -> CGFloat {
    size.value(context: context, shouldUseFixedDefaultSize: useFixedDefaultSize) * textScale
  }

  /// Whether the font uses the fixed default size, as `monospace` does.
  private var useFixedDefaultSize: Bool {
    families.count == 1 && families[0] == FontCacheCoreText.familyNamesData[.monospace]
  }

  /// A new description of the font. Making a font cascade changes its description, so renderings that run at the
  /// same time must not share one.
  private func makeDescription() -> FontCascadeDescription {
    let description = FontCascadeDescription()
    description.setFamilies(familyNames: families)
    if let specifiedLocale {
      description.setSpecifiedLocale(locale: specifiedLocale)
    }
    return description
  }

  func fontCascade(textScale: Double, context: any SVGLengthContext) -> FontCascade {
    Self.createFontCascade(size: size, weight: weight, fontDescription: makeDescription(), textScale: textScale, context: context)
  }

  static func createFontCascade(
    size: Size?, weight: Weight?, fontDescription: FontCascadeDescription,
    textScale: Double, context: any SVGLengthContext
  ) -> FontCascade {
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

  func ctFont(context: any SVGLengthContext, textScale: Double = 1.0) -> CTFont {
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
      case .number(let value): return .init(value)
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
          case .number(let value):
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
          case .number(let value):
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
      case .number(let value):
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
      case .length(let value): value.description
      }
    }

    func value(context: any SVGLengthContext, shouldUseFixedDefaultSize: Bool) -> CGFloat {
      switch self {
      case .xxSmall: 9
      case .xSmall: shouldUseFixedDefaultSize ? 9 : 10
      case .small: shouldUseFixedDefaultSize ? 10 : 13
      case .medium: shouldUseFixedDefaultSize ? Self.defaultFixedFontSize : Self.defaultFontSize
      case .large: shouldUseFixedDefaultSize ? 16 : 18
      case .xLarge: shouldUseFixedDefaultSize ? 20 : 24
      case .xxLarge: shouldUseFixedDefaultSize ? 26 : 32
      case .xxxLarge: shouldUseFixedDefaultSize ? 40 : 48
      case .smaller, .larger: preconditionFailure("a computed font size isn't relative")
      case .length(let length):
        length.fontValue(context: context)
      }
    }

  }
}
