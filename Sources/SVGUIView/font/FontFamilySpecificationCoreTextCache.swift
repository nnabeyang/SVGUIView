import Foundation

class FontFamilySpecificationCoreTextCache {
  static var shared: FontFamilySpecificationCoreTextCache {
    FontCache.shared.fontFamilySpecificationCoreTextCache
  }

  private let lock = NSLock()

  private var fonts = [FontFamilySpecificationKey: FontPlatformData]()

  func font(for key: FontFamilySpecificationKey) -> FontPlatformData? {
    lock.lock()
    defer { lock.unlock() }
    return fonts[key]
  }

  func font(_ value: FontPlatformData?, for key: FontFamilySpecificationKey) {
    lock.lock()
    defer { lock.unlock() }
    fonts[key] = value
  }
}
