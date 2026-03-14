import SVGSnapshotAssets
import SnapshotTesting
import SwiftUI
import XCTest

extension XCTestCase {
  public func assertSnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record recording: Bool = false,
    timeout: TimeInterval = 5,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
  ) {
    let fileUrl = URL(fileURLWithPath: "\(file)", isDirectory: false)
    let fileName = fileUrl.deletingPathExtension().lastPathComponent
    let snapshotsBaseUrl = fileUrl.deletingLastPathComponent()
    let localSnapshotDirectoryUrl = snapshotsBaseUrl.appendingPathComponent("__Snapshots__").appendingPathComponent(fileName)
    let snapshotDirectory: String?
    if FileManager.default.fileExists(atPath: localSnapshotDirectoryUrl.path(percentEncoded: false)) {
      snapshotDirectory = localSnapshotDirectoryUrl.path(percentEncoded: false)
    } else if FileManager.default.fileExists(atPath: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "__Snapshots__", fileName).path(percentEncoded: false)) {
      snapshotDirectory = SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "__Snapshots__", fileName).path(percentEncoded: false)
    } else {
      snapshotDirectory = nil
    }
    let failure = verifySnapshot(
      of: try value(),
      as: snapshotting,
      named: name,
      record: recording,
      snapshotDirectory: snapshotDirectory,
      timeout: timeout,
      file: file,
      testName: testName,
      line: line
    )
    guard let message = failure else { return }
    XCTFail(message, file: file, line: line)
  }

}
