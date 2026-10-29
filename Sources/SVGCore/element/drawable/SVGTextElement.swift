import CoreGraphics
import CoreText
import Foundation

enum TextAnchor: String, CaseIterable {
  case start
  case middle
  case end
}

final class SVGTextElement: ShapeGeometry {
  static var type: SVGElementName {
    .text
  }

  var type: SVGElementName {
    .text
  }

  let base: SVGBaseElement
  let text: String
  let positions: CharacterPositions

  init(base: SVGBaseElement, text: String, attributes: [String: String]) {
    self.base = base
    self.text = base.style.whiteSpace.processed(text)
    positions = CharacterPositions(attributes: attributes)
  }

  /// The text laid out with the positions of its characters, or `nil` if it isn't drawn.
  private func layout(context: any GeometryContext) -> TextLayout? {
    TextLayout(text: text, positions: positions, anchor: style.textAnchor, context: context) {
      getLine(text: $0, context: context)
    }
  }

  private func getLine(text: String, context: any SVGLengthContext) -> CTLine? {
    var attributes: [CFString: Any] = [:]
    let font = style.font
    let modifiedFont: SVGUIFont? = {
      switch font.size {
      case .length(.number(let value)), .length(.pixel(let value)):
        if value == 0 {
          return nil
        }
        if value < 0 {
          return SVGUIFont(name: style.fontFamily, size: .medium, weight: style.fontWeight)
        }
      default:
        break
      }
      return font
    }()
    guard let modifiedFont = modifiedFont else { return nil }
    attributes[kCTFontAttributeName] = modifiedFont.ctFont(context: context, textScale: context.textScale)

    guard
      let attributedText = CFAttributedStringCreate(
        kCFAllocatorDefault,
        text as NSString,
        attributes as CFDictionary)
    else { return nil }
    return CTLineCreateWithAttributedString(attributedText)
  }

  /// The bounds of the lines of text, which are larger than the bounds of its glyphs.
  func frame(in context: any GeometryContext, path _: CGPath?) -> CGRect {
    layout(context: context)?.frame ?? .zero
  }

  /// The outlines of the glyphs of the text.
  func path(in context: any GeometryContext) -> CGPath? {
    layout(context: context)?.path
  }

  static func withUnsafeMutablePointer<T>(array: inout [T], from: Int) -> UnsafeMutablePointer<T> {
    let baseAddress = array.withUnsafeMutableBufferPointer { $0.baseAddress! }
    return baseAddress.advanced(by: from)
  }
}

extension SVGTextElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case text
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(text, forKey: .text)
  }
}
