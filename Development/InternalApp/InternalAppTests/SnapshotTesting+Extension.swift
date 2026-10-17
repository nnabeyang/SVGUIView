import Foundation
import SVGSnapshotReferences
import SVGUIView
import SnapshotTesting
import Testing
import UIKit

/// Renders an SVG file and compares the image with its reference image.
///
/// Reference images are read from `__Snapshots__/<environment>/<test file>/` next to the test file when that
/// directory exists, and otherwise from the `SVGSnapshotReferences` bundle. New reference images, and all of
/// them when `SNAPSHOT_TESTING_RECORD` is `all`, are written next to the test file. When a comparison fails,
/// swift-snapshot-testing attaches the reference, the rendered image and their difference to the test result.
@MainActor
func assertSVGSnapshot(
  of file: SVGFile,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async throws {
  let sourceLocation = SourceLocation(
    fileID: "\(fileID)", filePath: "\(filePath)", line: Int(line), column: Int(column))
  try SnapshotEnvironment.requireExpected(sourceLocation: sourceLocation)

  let view = try #require(SVGUIView(contentsOf: file.url), "Couldn't read \(file.url.lastPathComponent)", sourceLocation: sourceLocation)
  view.contentMode = .scaleAspectFit
  view.frame = UIScreen.main.bounds
  view.layoutIfNeeded()
  // A document without a root `svg` element, such as one in another namespace, draws nothing, and its
  // reference image is empty. A rendering that times out is also compared as an empty image.
  let image = await view.takeSnapshot() ?? UIGraphicsImageRenderer(size: view.bounds.size).image { _ in }

  // `circle(_:)` becomes `circle`, so that reference images are named `circle.<file name>.png`.
  let testName = String(testName.prefix { $0 != "(" })
  let failure = verifySnapshot(
    of: image,
    as: .image(precision: 0.999, perceptualPrecision: 0.98),
    named: file.name,
    record: recordMode,
    snapshotDirectory: snapshotDirectory(filePath: filePath),
    fileID: fileID,
    file: filePath,
    testName: testName,
    line: line,
    column: column
  )
  if let failure {
    Issue.record(Comment(rawValue: failure), sourceLocation: sourceLocation)
  }
}

/// The record mode that `SNAPSHOT_TESTING_RECORD` sets, such as `all`, or `nil` for the default.
private let recordMode = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
  .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

private func snapshotDirectory(filePath: StaticString) -> String {
  let fileURL = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
  let environment = SnapshotEnvironment.expected.directoryName
  let suite = fileURL.deletingPathExtension().lastPathComponent
  let local = fileURL.deletingLastPathComponent().appending(components: "__Snapshots__", environment, suite)
  let bundled = SnapshotReferences.bundle.bundleURL.appending(components: "Resources", "__Snapshots__", environment, suite)
  let fileManager = FileManager.default
  // Recording must never write into the bundle.
  if recordMode != .all, !fileManager.fileExists(atPath: local.path(percentEncoded: false)),
    fileManager.fileExists(atPath: bundled.path(percentEncoded: false))
  {
    return bundled.path(percentEncoded: false)
  }
  return local.path(percentEncoded: false)
}
