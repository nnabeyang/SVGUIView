import Foundation
import SVGSnapshotReferences
import SVGTestSuite
import SnapshotTesting
import Testing
import UIKit

@testable import SVGUIView

/// Renders an SVG file and compares the image with its reference image.
///
/// With a time, the file is rendered as it is at that time of its animations, and the name of the reference image
/// ends with the time in milliseconds, such as `-500ms`.
///
/// The file is rendered in a view of the size of the screen, or with `atIntrinsicSize`, of the intrinsic content size
/// of the view, so that the size of the reference image is the size of the document.
///
/// Reference images are read from `__Snapshots__/<environment>/<test file>/` next to the test file when that
/// directory exists, and otherwise from the `SVGSnapshotReferences` bundle. New reference images, and all of
/// them when `SNAPSHOT_TESTING_RECORD` is `all`, are written next to the test file. When a comparison fails,
/// swift-snapshot-testing attaches the reference, the rendered image and their difference to the test result.
@MainActor
func assertSVGSnapshot(
  of file: SVGFile,
  at time: Duration? = nil,
  atIntrinsicSize: Bool = false,
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
  // The tests check what a rendering draws, not how fast. On CI, many renderings run in parallel and can be
  // slow, so the timeout is longer than the default and only catches a rendering that never ends.
  view.configuration = SVGUIViewConfiguration(
    timeoutDuration: .seconds(60), externalResources: NetworkCopies.resources)
  view.frame = CGRect(origin: .zero, size: atIntrinsicSize ? view.intrinsicContentSize : UIScreen.main.bounds.size)
  view.layoutIfNeeded()
  // The resources of the network are read from their copies in the test suite.
  let rendered: Result<UIImage, SVGRenderingError> = await SVGUIView.$resourceFetch.withValue(NetworkCopies.fetch) {
    do throws(SVGRenderingError) {
      return .success(try await view.takeSnapshot(at: time ?? .zero))
    } catch {
      return .failure(error)
    }
  }
  let image: UIImage
  do {
    image = try rendered.get()
  } catch .missingRootElement {
    // A document without a root `svg` element, such as one in another namespace, draws nothing, and its
    // reference image is empty.
    image = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in }
  } catch .timedOut {
    Issue.record(
      "Rendering \(file.name) took longer than \(view.configuration.timeoutDuration)", sourceLocation: sourceLocation)
    return
  } catch .cancelled {
    Issue.record("Rendering \(file.name) was cancelled", sourceLocation: sourceLocation)
    return
  } catch .allocationFailed {
    Issue.record("The memory to render \(file.name) into couldn't be allocated", sourceLocation: sourceLocation)
    return
  } catch .zeroSizedRect {
    Issue.record("The view has no size to render \(file.name) into: \(view.frame)", sourceLocation: sourceLocation)
    return
  }

  // `circle(_:)` becomes `circle`, so that reference images are named `circle.<file name>.png`.
  let testName = String(testName.prefix { $0 != "(" })
  let failure = verifySnapshot(
    of: image,
    as: .wideGamutImage(precision: 0.999, perceptualPrecision: 0.98),
    named: time.map { "\(file.name)-\(milliseconds(of: $0))ms" } ?? file.name,
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

extension Snapshotting where Value == UIImage, Format == UIImage {
  /// Compares images as `image(precision:perceptualPrecision:)` does, and, where either image is of a wide gamut,
  /// also in Display P3.
  ///
  /// `image(precision:perceptualPrecision:)` draws both images into sRGB before it compares them, so a color
  /// outside sRGB that is clamped to sRGB matches the same color rendered in Display P3. Images of sRGB are compared
  /// only in sRGB, as before.
  static func wideGamutImage(precision: Float, perceptualPrecision: Float) -> Snapshotting {
    let image = Diffing<UIImage>.image(precision: precision, perceptualPrecision: perceptualPrecision)
    return Snapshotting(
      pathExtension: "png",
      diffing: .diff(toData: image.toData, fromData: image.fromData) { reference, rendered in
        if let failure = image.diffV2(reference, rendered) { return failure }
        guard let message = wideGamutDifference(reference, rendered, precision: precision) else { return nil }
        return (
          message,
          [.data(image.toData(reference), name: "reference.png"), .data(image.toData(rendered), name: "failure.png")]
        )
      })
  }
}

/// How much a component of a pixel in Display P3, out of 255, can differ between two images that match.
///
/// It is as large as the differences of the edges of shapes, and smaller than the difference between a color
/// outside sRGB and the color clamped to sRGB, such as 51 in the green of `color(display-p3 1 0 0)`.
private let wideGamutTolerance = 16

/// Why two images of the same size differ in Display P3, or `nil` if they match or neither is of a wide gamut.
///
/// - Parameter precision: The fraction of the pixels that must match.
func wideGamutDifference(_ reference: UIImage, _ rendered: UIImage, precision: Float) -> String? {
  guard let reference = reference.cgImage, let rendered = rendered.cgImage,
    reference.width == rendered.width, reference.height == rendered.height,
    reference.colorSpace?.isWideGamutRGB == true || rendered.colorSpace?.isWideGamutRGB == true
  else { return nil }
  guard let referencePixels = displayP3Pixels(of: reference), let renderedPixels = displayP3Pixels(of: rendered)
  else { return "The images couldn't be drawn in Display P3." }
  let pixelCount = reference.width * reference.height
  var differentPixels = 0
  var largest = 0
  referencePixels.withUnsafeBufferPointer { referencePixels in
    renderedPixels.withUnsafeBufferPointer { renderedPixels in
      for pixel in 0..<pixelCount {
        var differs = false
        for component in pixel * 4..<pixel * 4 + 4 {
          let difference = abs(Int(referencePixels[component]) - Int(renderedPixels[component]))
          largest = max(largest, difference)
          differs = differs || difference > wideGamutTolerance
        }
        if differs { differentPixels += 1 }
      }
    }
  }
  let allowed = Int((1 - precision) * Float(pixelCount))
  guard differentPixels > allowed else { return nil }
  return
    "\(differentPixels) of \(pixelCount) pixels differ in Display P3, by up to \(largest) out of 255, more than \(allowed) can"
}

/// The red, green, blue and alpha of the pixels of an image, premultiplied, in 8 bits of Display P3.
private func displayP3Pixels(of image: CGImage) -> [UInt8]? {
  guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
  var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
  let drawn = pixels.withUnsafeMutableBytes { pixels in
    guard
      let context = CGContext(
        data: pixels.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return true
  }
  return drawn ? pixels : nil
}

/// The time in whole milliseconds, for the names of reference images, which can't have a period.
private func milliseconds(of time: Duration) -> Int64 {
  let (seconds, attoseconds) = time.components
  return seconds * 1000 + attoseconds / 1_000_000_000_000_000
}

/// The record mode that `SNAPSHOT_TESTING_RECORD` sets, such as `all`, or `nil` for the default.
private let recordMode = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
  .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

private func snapshotDirectory(filePath: StaticString) -> String {
  let fileURL = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
  let environment = SnapshotEnvironment.expected.directoryName
  let suite = fileURL.deletingPathExtension().lastPathComponent
  let local = fileURL.deletingLastPathComponent().appending(components: "__Snapshots__", environment, suite)
  let bundled = SnapshotReferences.bundle.bundleURL.appending(components: "__Snapshots__", environment, suite)
  let fileManager = FileManager.default
  // Recording must never write into the bundle.
  if recordMode != .all, !fileManager.fileExists(atPath: local.path(percentEncoded: false)),
    fileManager.fileExists(atPath: bundled.path(percentEncoded: false))
  {
    return bundled.path(percentEncoded: false)
  }
  return local.path(percentEncoded: false)
}
