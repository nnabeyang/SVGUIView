import CoreText
import UIKit
import _SPI

enum FontTypeForPreparation {
  case systemFont
  case nonSystemFont
}

enum ApplyTraitsVariations {
  case no
  case yes
}

struct SpecialCaseFontLookupResult {
  let unrealizedCoreTextFont: UnrealizedCoreTextFont
  let fontTypeForPreparation: FontTypeForPreparation
}

enum SystemFontKind: UInt8 {
  case systemUI
  case uiSerif
  case uiMonospace
  case uiRounded
  case textStyle
}

enum AllowUserInstalledFonts {
  case no
  case yes
}

extension SVGUIView {
  nonisolated static let familyNamesData: FamilyNames = [
    "-webkit-cursive",
    "-webkit-fantasy",
    "-webkit-monospace",
    "-webkit-pictograph",
    "-webkit-sans-serif",
    "-webkit-serif",
    "-webkit-standard",
    "-webkit-system-ui",
  ]

  nonisolated static func systemFontCascadeList(
    description: FontDescription, cssFamily: String,
    systemFontKind: SystemFontKind, allowUserInstalledFonts: AllowUserInstalledFonts
  ) -> [CTFontDescriptor] {
    SystemFontDatabaseCoreText.shared.cascadeList(
      description: description, cssFamily: cssFamily,
      systemFontKind: systemFontKind, allowUserInstalledFonts: allowUserInstalledFonts)
  }

  nonisolated static func fontDescriptorWithFamilySpecialCase(
    familyName: String, fontDescription: FontDescription,
    size _: Double, allowUserInstalledFonts: AllowUserInstalledFonts
  ) -> SpecialCaseFontLookupResult? {
    var systemDesign: SystemFontKind?
    if Self.equalLettersIgnoringASCIICase(string: familyName, literal: "ui-serif") {
      systemDesign = .uiSerif
    } else if Self.equalLettersIgnoringASCIICase(string: familyName, literal: "ui-monospace") {
      systemDesign = .uiMonospace
    } else if Self.equalLettersIgnoringASCIICase(string: familyName, literal: "ui-rounded") {
      systemDesign = .uiRounded
    } else if Self.equalLettersIgnoringASCIICase(string: familyName, literal: "-webkit-system-font")
      || Self.equalLettersIgnoringASCIICase(string: familyName, literal: "-apple-system")
      || Self.equalLettersIgnoringASCIICase(string: familyName, literal: "-apple-system-font")
      || Self.equalLettersIgnoringASCIICase(string: familyName, literal: "system-ui")
      || Self.equalLettersIgnoringASCIICase(string: familyName, literal: "ui-sans-serif")
    {
      systemDesign = .systemUI
    }

    if let systemDesign = systemDesign {
      let cascadeList = Self.systemFontCascadeList(
        description: fontDescription, cssFamily: familyName, systemFontKind: systemDesign,
        allowUserInstalledFonts: allowUserInstalledFonts)
      if cascadeList.isEmpty {
        return nil
      }
      return .init(
        unrealizedCoreTextFont: .init(descriptor: cascadeList[0]),
        fontTypeForPreparation: .systemFont)
    }
    return nil
  }

  nonisolated static func findClosestFont(familyFonts: FontDatabase.InstalledFontFamily, fontSelectionRequest: FontSelectionRequest) -> FontDatabase.InstalledFont? {
    let capabilities = familyFonts.installedFonts.map(\.capabilities)
    let algorithm = FontSelectionAlgorithm(request: fontSelectionRequest, capabilities: capabilities, capabilitiesBounds: familyFonts.capabilities)
    guard let index = algorithm.indexOfBestCapabilities(), index < familyFonts.installedFonts.count else { return nil }
    return familyFonts.installedFonts[index]
  }

  nonisolated static func platformFontLookupWithFamily(fontDatabase: FontDatabase, familyName: String, request: FontSelectionRequest) -> CTFontDescriptor? {
    let familyFonts = fontDatabase.collectionForFamily(familyName: familyName)
    guard !familyFonts.isEmpty else {
      guard let postScriptFont = fontDatabase.fontForPostScriptName(postScriptName: familyName) else {
        return nil
      }
      return postScriptFont.fontDescriptor
    }
    guard let installedFonts = findClosestFont(familyFonts: familyFonts, fontSelectionRequest: request) else { return nil }
    return installedFonts.fontDescriptor
  }

  nonisolated static func fontWithFamily(fontDatabase: FontDatabase, familyName: String, fontDescription: FontDescription, fontCreationContext: FontCreationContext, size: Double) -> CTFont? {
    guard !familyName.isEmpty else { return nil }

    if let lookupResult = fontDescriptorWithFamilySpecialCase(
      familyName: familyName, fontDescription: fontDescription,
      size: size, allowUserInstalledFonts: fontDescription.shouldAllowUserInstalledFonts)
    {
      lookupResult.unrealizedCoreTextFont.setSize(size: size)
      SystemFontDatabaseCoreText.addAttributesForInstalledFonts(
        attributes: &lookupResult.unrealizedCoreTextFont.attributes,
        allowUserInstalledFonts: fontDescription.shouldAllowUserInstalledFonts)
      return preparePlatformFont(
        originalFont: lookupResult.unrealizedCoreTextFont,
        fontDescription: fontDescription, fontCreationContext: fontCreationContext,
        fontTypeForPreparation: lookupResult.fontTypeForPreparation)
    }

    guard let descriptor = platformFontLookupWithFamily(fontDatabase: fontDatabase, familyName: familyName, request: fontDescription.fontSelectionRequest) else {
      return nil
    }
    let unrealizedFont = UnrealizedCoreTextFont(descriptor: descriptor)
    unrealizedFont.setSize(size: size)
    return preparePlatformFont(
      originalFont: unrealizedFont, fontDescription: fontDescription,
      fontCreationContext: fontCreationContext, fontTypeForPreparation: .nonSystemFont)
  }

  nonisolated static func equalLettersIgnoringASCIICase(string: String, literal: String) -> Bool {
    string.caseInsensitiveCompare(literal) == .orderedSame
  }

  nonisolated static func preparePlatformFont(
    originalFont: UnrealizedCoreTextFont, fontDescription: FontDescription,
    fontCreationContext: FontCreationContext,
    fontTypeForPreparation _: FontTypeForPreparation, applyTraitsVariations: ApplyTraitsVariations = .yes
  ) -> CTFont? {
    originalFont.modifyFromContext(
      fontDescription: fontDescription, fontCreationContext: fontCreationContext,
      applyTraitsVariations: applyTraitsVariations)
    return originalFont.realize()
  }

  static var matchWords: [String] {
    ["Arabic", "Pashto", "Urdu"]
  }

  static func similarFontName(request: FontSelectionRequest, familyName: String) -> String? {
    guard familyName.isEmpty else { return nil }
    if equalLettersIgnoringASCIICase(string: familyName, literal: "monaco") || equalLettersIgnoringASCIICase(string: familyName, literal: "menlo") {
      return "courier"
    }
    if equalLettersIgnoringASCIICase(string: familyName, literal: "lucida grande") {
      return "verdana"
    }
    for matchWord in matchWords {
      if equalLettersIgnoringASCIICase(string: familyName, literal: matchWord) {
        return FontSelectionValue.isFontWeightBold(fontWeight: request.weight) ? "GeezaPro-Bold" : "GeezaPro"
      }
    }
    return nil
  }
}
