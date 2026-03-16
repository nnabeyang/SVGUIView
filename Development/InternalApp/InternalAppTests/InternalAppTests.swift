import SVGSnapshotAssets
import SVGUIView
import SnapshotTesting
import XCTest

extension Snapshotting
where Value == SVGUIView, Format == UIImage {
  static func image(precision: Float = 1) -> Snapshotting {
    .init(
      pathExtension: "png",
      diffing: .image(precision: precision),
      asyncSnapshot: { view in
        Async<UIImage> { callback in
          Task { @MainActor in
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            let size = view.bounds.size

            let image = await view.takeSnapshot() ?? UIGraphicsImageRenderer(size: size).image { _ in }
            callback(image)
          }
        }
      }
    )
  }
}

class SVGUIViewBasicSnapshotsTests: XCTestCase {
  @inline(__always)
  func testBase(root: URL, testName: String = #function, fileName: StaticString = #file) throws {
    if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
      for case let fileUrl as URL in enumerator {
        do {
          let fileAttributes = try fileUrl.resourceValues(forKeys: [.isRegularFileKey])
          if fileAttributes.isRegularFile!, fileUrl.pathExtension == "svg" {
            let name = generateSnapshotName(fileUrl: fileUrl)
            print(name)
            let view = SVGUIView(contentsOf: fileUrl)!
            view.contentMode = .scaleAspectFit
            view.frame = UIScreen.main.bounds
            assertSnapshot(of: view, as: .image(precision: 0.92), named: name, file: fileName, testName: testName)
          }
        } catch { print(error, fileUrl) }
      }
    }
  }

  private func generateSnapshotName(fileUrl: URL) -> String {
    let deviceName = UIDevice.current.machineIdentifier
      .lowercased()
      .replacingOccurrences(of: ",", with: "_")
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(version.majorVersion).\(version.minorVersion)"
    let baseName = fileUrl.deletingPathExtension().lastPathComponent
    return "\(baseName)_\(deviceName)_\(osVersion)"
  }
}

extension UIDevice {
  var machineIdentifier: String {
    #if targetEnvironment(simulator)
      return (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unknown_simulator")
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .joined()
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
