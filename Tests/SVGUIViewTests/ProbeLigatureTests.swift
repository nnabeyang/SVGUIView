import CoreGraphics
import CoreText
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// A temporary probe for svg_ui_view-367. Not to be committed.
@MainActor
@Suite("Probe ligatures")
struct ProbeLigatureTests {
  private func glyphs(_ font: CTFont, _ extra: [NSAttributedString.Key: Any] = [:]) -> Int {
    var attributes: [NSAttributedString.Key: Any] = [.font: font]
    attributes.merge(extra) { $1 }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "fi", attributes: attributes))
    return CTLineGetGlyphCount(line)
  }

  @Test func probe() async throws {
    var lines = ["languages: \(Locale.preferredLanguages)"]
    for family in ["Times New Roman", "Hoefler Text", "Baskerville", "Palatino", "Didot", "Georgia", "Helvetica Neue"] {
      let plain = CTFontCreateWithName(family as CFString, 40, nil)
      let url = CTFontCopyAttribute(plain, kCTFontURLAttribute) as? URL
      let version = CTFontCopyName(plain, kCTFontVersionNameKey) as String? ?? "-"
      var traits = [CFString: Any]()
      traits[kCTFontWeightTrait] = 0.0 as CFNumber
      traits[kCTFontWidthTrait] = 0.0 as CFNumber
      traits[kCTFontSlantTrait] = 0.0 as CFNumber
      let modified = CTFontCreateCopyWithAttributes(
        plain, 40, nil, CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary))
      let installed = plain
      let view = SVGUIView(
        frame: CGRect(x: 0, y: 0, width: 400, height: 300),
        data: Data(
          (##"<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" font-size="40"><text id="t" x="10" y="50" font-family="\##(family)">fia</text></svg>"##)
            .utf8))
      let layout = try #require(await view.document.element(id: "t")?.textLayout())
      let svg = layout.characters[0] == layout.characters[1] ? 1 : 2
      lines.append(
        "\(family): name \(CTFontCopyFamilyName(plain)) ps \(CTFontCopyPostScriptName(plain)) v \(version) file \(url?.lastPathComponent ?? "-") | plain \(glyphs(plain)) en \(glyphs(plain, [NSAttributedString.Key(kCTLanguageAttributeName as String): "en"])) ja \(glyphs(plain, [NSAttributedString.Key(kCTLanguageAttributeName as String): "ja"])) traits \(glyphs(modified)) traitsPS \(CTFontCopyPostScriptName(modified)) installed \(glyphs(installed)) | svg \(svg)"
      )
    }
    Issue.record(Comment(rawValue: lines.joined(separator: "\n")))
  }
}
