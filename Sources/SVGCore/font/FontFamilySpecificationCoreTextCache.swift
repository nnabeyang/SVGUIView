import Foundation
import Synchronization

final class FontFamilySpecificationCoreTextCache: Sendable {
  static var shared: FontFamilySpecificationCoreTextCache {
    FontCache.shared.fontFamilySpecificationCoreTextCache
  }

  private let fonts = Mutex([FontFamilySpecificationKey: FontPlatformData]())

  func font(for key: FontFamilySpecificationKey) -> FontPlatformData? {
    fonts.withLock { $0[key] }
  }

  /// Keeps the data of a font, or removes the data of the key for `nil`.
  func font(_ value: FontPlatformData?, for key: FontFamilySpecificationKey) {
    fonts.withLock { $0[key] = value }
  }
}
