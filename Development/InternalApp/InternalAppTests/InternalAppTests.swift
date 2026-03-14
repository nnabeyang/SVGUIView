import SVGSnapshotAssets
import SVGUIView
import SnapshotTesting
import XCTest

extension Snapshotting
where Value == SVGUIView, Format == UIImage {
  static let image = Snapshotting(
    pathExtension: "png", diffing: .image,
    asyncSnapshot: { view in
      Async<UIImage> { callback in
        Task {
          let size = await view.bounds.size
          let image = await view.takeSnapshot() ?? UIGraphicsImageRenderer(size: size).image(actions: { _ in })
          callback(image)
        }
      }
    }
  )
}

class SVGUIViewBasicSnapshotsTests: XCTestCase {
  @inline(__always)
  func testBase(root: URL, testName: String = #function, fileName: StaticString = #file) throws {
    if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
      for case let fileUrl as URL in enumerator {
        do {
          let fileAttributes = try fileUrl.resourceValues(forKeys: [.isRegularFileKey])
          if fileAttributes.isRegularFile!, fileUrl.pathExtension == "svg" {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let name = "\(fileUrl.deletingPathExtension().lastPathComponent)_\(version.majorVersion).\(version.minorVersion)"
            print(name)
            let view = SVGUIView(contentsOf: fileUrl)!
            view.contentMode = .scaleAspectFit
            view.frame = UIScreen.main.bounds
            assertSnapshot(of: view, as: .image, named: name, file: fileName, testName: testName)
          }
        } catch { print(error, fileUrl) }
      }
    }
  }
}
