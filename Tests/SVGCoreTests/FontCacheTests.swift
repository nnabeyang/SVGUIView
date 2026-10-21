import CoreText
import Testing

@testable import SVGCore

@Suite("Font caches")
struct FontCacheTests {
  /// Font sizes to look up at the same time, so that each lookup adds a new entry to the shared caches.
  private static let sizes = (1...500).map { 1000 + Double($0) / 8 }

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
