import CoreGraphics
import CoreText
import Testing

@testable import SVGCore

@Suite("Font caches")
struct FontCacheTests {
  /// Font sizes to look up at the same time, so that each lookup adds a new entry to the shared caches.
  private static let sizes = (1...500).map { 1000 + Double($0) / 8 }

  @Test("a font with font-style italic or oblique has an italic face, and a normal one doesn't")
  func italicFont() {
    struct Context: SVGLengthContext {
      var viewBoxSize: CGSize { .zero }
      var font: SVGUIFont? { nil }
      var textScale: Double { 1 }
      var rootFont: SVGUIFont? { nil }
      var viewPort: CGRect { .zero }
      var writingMode: WritingMode? { nil }
    }
    func isItalic(_ style: FontStyle) -> Bool {
      let font = SVGUIFont(name: "Times New Roman", size: .length(.pixel(20)), weight: .normal, style: style)
        .ctFont(context: Context())
      return CTFontGetSymbolicTraits(font).contains(.traitItalic)
    }
    #expect(isItalic(.italic))
    #expect(isItalic(.oblique(nil)))
    #expect(!isItalic(.normal))
  }

  @Test("system font cascade lists can be looked up from many tasks at once")
  func cascadeListsConcurrently() async {
    await withTaskGroup(of: Void.self) { group in
      for size in Self.sizes {
        group.addTask {
          var parameters = SystemFontDatabaseCoreText.CascadeListParameters()
          parameters.fontName = "system-ui"
          parameters.size = size
          _ = SystemFontDatabaseCoreText.shared.cascadeList(parameters: parameters, systemFontKind: .systemUI)
        }
      }
    }
  }

  @Test("a cached cascade list is returned for the same parameters")
  func cascadeListIsCached() throws {
    let database = SystemFontDatabaseCoreText.shared
    var parameters = SystemFontDatabaseCoreText.CascadeListParameters()
    parameters.fontName = "system-ui"
    parameters.size = 999.5
    let first = database.cascadeList(parameters: parameters, systemFontKind: .systemUI)
    let second = database.cascadeList(parameters: parameters, systemFontKind: .systemUI)
    try #require(first.count == second.count)
    #expect(zip(first, second).allSatisfy { $0 === $1 })
  }

  @Test("fonts can be looked up from many tasks at once")
  func fontsConcurrently() async {
    await withTaskGroup(of: Void.self) { group in
      for size in Self.sizes {
        group.addTask {
          let description = FontCascadeDescription()
          description.computedSize = size
          description.shouldAllowUserInstalledFonts = .no
          _ = FontCache.shared.fontForFamily(fontDescription: description, familyName: "Helvetica")
        }
      }
    }
  }
}
