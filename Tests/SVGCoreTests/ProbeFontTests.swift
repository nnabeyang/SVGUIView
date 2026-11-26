import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import SVGCore

/// A temporary probe for svg_ui_view-367. Not to be committed.
@Suite("Probe fonts")
struct ProbeFontTests {
  struct Context: SVGLengthContext {
    var viewBoxSize: CGSize { .zero }
    var font: SVGUIFont? { nil }
    var textScale: Double { 1 }
    var rootFont: SVGUIFont? { nil }
    var viewPort: CGRect { .zero }
    var writingMode: WritingMode? { nil }
  }

  private func glyphs(_ font: CTFont) -> Int {
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: "fi", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]) as CFAttributedString)
    return CTLineGetGlyphCount(line)
  }

  private func describe(_ font: CTFont) -> String {
    let attributes = CTFontDescriptorCopyAttributes(CTFontCopyFontDescriptor(font)) as NSDictionary
    let keys = (attributes.allKeys as? [String] ?? []).sorted().filter { $0 != "NSFontNameAttribute" }
    let values = keys.map { "\($0)=\(attributes[$0].map { String(describing: $0) }?.replacingOccurrences(of: "\n", with: " ") ?? "-")" }
    let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
    return
      "ps \(CTFontCopyPostScriptName(font)) file \(url?.path ?? "-") glyphs \(glyphs(font)) attrs [\(values.joined(separator: "; "))]"
  }

  @Test func probe() {
    var lines = ["languages: \(Locale.preferredLanguages)"]
    for family in ["Times New Roman", "Hoefler Text", "Georgia", "Helvetica Neue"] {
      let plain = CTFontCreateWithName(family as CFString, 40, nil)
      let svg = SVGUIFont(name: "'\(family)'", size: .length(.pixel(40)), weight: .normal, style: .normal)
        .ctFont(context: Context())
      let variations: [CFNumber: CFNumber] = [
        0x7767_6874 as CFNumber: 400 as CFNumber, 0x7764_7468 as CFNumber: 100 as CFNumber,
        0x736C_6E74 as CFNumber: 0 as CFNumber,
      ]
      let varied = CTFontCreateCopyWithAttributes(
        plain, 40, nil,
        CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: variations] as CFDictionary))
      lines.append(
        "\(family)\n  plain: \(describe(plain))\n  plain+variations: \(describe(varied))\n  svg: \(describe(svg))")
    }
    Issue.record(Comment(rawValue: lines.joined(separator: "\n")))
  }
}
