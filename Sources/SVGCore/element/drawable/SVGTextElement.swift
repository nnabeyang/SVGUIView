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
  let x: SVGLength?
  let y: SVGLength?

  init(base: SVGBaseElement, text: String, attributes: [String: String]) {
    self.base = base
    self.text = base.style.whiteSpace.processed(text)
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
  }

  private func getLine(context: any SVGLengthContext) -> CTLine? {
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

  /// The bounds of the line of text, which are larger than the bounds of its glyphs.
  func frame(in context: any GeometryContext, path _: CGPath?) -> CGRect {
    guard let line = getLine(context: context) else { return .zero }
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    let textScale = context.textScale
    var transform = CGAffineTransform(translationX: x, y: y)
      .scaledBy(x: 1.0 / textScale, y: -1.0 / textScale)
    let rect = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
    transform = transform.translatedBy(x: anchorOffset(width: rect.width), y: 0)
    return rect.applying(transform)
  }

  /// The outlines of the glyphs of the text.
  func path(in context: any GeometryContext) -> CGPath? {
    guard let line = getLine(context: context) else { return nil }
    let letters = CGMutablePath()
    let runs = CTLineGetGlyphRuns(line)
    for i in 0..<CFArrayGetCount(runs) {
      let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
      let fontPointer = CFDictionaryGetValue(CTRunGetAttributes(run), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
      let runFont = unsafeBitCast(fontPointer, to: CTFont.self)

      let length = CTRunGetGlyphCount(run) as Int
      var glyphs = [CGGlyph](repeating: .init(), count: length)
      var positions = [CGPoint](repeating: CGPoint(), count: length)
      let range = CFRange(location: 0, length: length)
      CTRunGetGlyphs(run, range, &glyphs)
      CTRunGetPositions(run, range, &positions)
      for index in 0..<glyphs.count {
        let position = positions[index]
        let glyph = glyphs[index]
        guard let letter = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
        letters.addPath(letter, transform: CGAffineTransform(translationX: position.x, y: position.y))
      }
    }

    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    let textScale = context.textScale
    var transform = CGAffineTransform(translationX: x, y: y)
      .scaledBy(x: 1.0 / textScale, y: -1.0 / textScale)

    let rect = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
    transform = transform.translatedBy(x: anchorOffset(width: rect.width), y: 0)
    return letters.applying(transform)
  }

  /// How far the line of text of the width moves along the line from `x`, so that its `text-anchor` is at `x`.
  private func anchorOffset(width: CGFloat) -> CGFloat {
    switch style.textAnchor {
    case .start: 0
    case .middle: -width / 2
    case .end: -width
    }
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
