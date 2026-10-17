import Foundation
import SVGTestSuite
import Testing
import UIKit

/// The parent of all snapshot test suites.
///
/// `.serialized` applies to every suite nested in it, so that one SVG file is rendered at a time, as with XCTest.
/// Rendering reads `UIScreen.main.scale` on the main actor for clip paths, masks, patterns, filters and text.
/// While other tests compare images on the main actor, those renderings run into their timeout.
@Suite(.serialized)
struct SnapshotTests {}

/// An SVG file of the test suite, passed to a parameterized test.
struct SVGFile: Sendable, CustomTestStringConvertible {
  let url: URL

  /// The file name without its extension, used as the name of the reference image.
  var name: String { url.deletingPathExtension().lastPathComponent }

  var testDescription: String { name }

  /// The SVG files under `Resources/w3c/<components>` of the test suite, sorted by path.
  static func all(in components: String...) -> [SVGFile] {
    let root = TestSuite.bundle.bundleURL.appending(components: "Resources", "w3c").appending(path: components.joined(separator: "/"), directoryHint: .isDirectory)
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    return enumerator.compactMap { $0 as? URL }
      .filter { url in
        url.pathExtension == "svg" && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      }
      .sorted { $0.path < $1.path }
      .map(SVGFile.init(url:))
  }
}

/// The device, OS and language that the reference images are recorded with.
///
/// The language matters because it decides the fallback fonts for text, such as the font for Han characters.
/// `InternalApp.xctestplan` sets it.
struct SnapshotEnvironment: Equatable, CustomStringConvertible {
  let device: String
  let osVersion: String
  let language: String

  /// The only environment that the snapshot tests run in.
  static let expected = SnapshotEnvironment(device: "iPhone 17e", osVersion: "27.0", language: "en")

  @MainActor
  static var current: SnapshotEnvironment {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return SnapshotEnvironment(
      device: UIDevice.current.deviceName,
      osVersion: "\(version.majorVersion).\(version.minorVersion)",
      language: Locale.preferredLanguages.first ?? "unknown")
  }

  /// The name of the directory that holds the reference images, such as `iphone17e_ios27.0`.
  var directoryName: String {
    let device = device.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    return "\(device)_ios\(osVersion)"
  }

  var description: String { "\(device) (iOS \(osVersion), \(language))" }

  /// Fails the current test unless it runs in the ``expected`` environment.
  @MainActor
  static func requireExpected(sourceLocation: SourceLocation = #_sourceLocation) throws {
    let current = current
    try #require(
      current == expected,
      "Snapshot tests must run on \(expected), because the reference images are recorded there, but this is \(current).",
      sourceLocation: sourceLocation)
  }
}

extension UIDevice {
  /// The simulated device's name, such as `iPhone 17e`, or the machine identifier of a real device.
  fileprivate var deviceName: String {
    #if targetEnvironment(simulator)
      return ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unknown simulator"
    #else
      var systemInfo = utsname()
      uname(&systemInfo)
      let machineMirror = Mirror(reflecting: systemInfo.machine)
      return machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
      }
    #endif
  }
}
