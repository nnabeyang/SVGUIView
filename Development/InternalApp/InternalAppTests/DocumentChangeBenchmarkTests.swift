import UIKit
import XCTest

@testable import SVGUIView

/// Measures how long a view takes to show a change of its document in every frame, as an app that edits shapes
/// makes while a finger drags one, for documents of several sizes.
///
/// The measurements compare the two ways that an app has to change what a view shows: giving the view the data of
/// the changed document, and changing an attribute of an element of the document of the view.
///
/// Besides the time and the time of the CPU of all the frames, each test reports, in the log and in an attachment,
/// how long a change kept the main thread, from the change until the view had started its rendering, and how long
/// the whole frame took, until the view showed the change.
///
/// Like ``BenchmarkTests``, the tests run only when `TEST_RUNNER_RUN_BENCHMARKS` is `1`, and are meant for the
/// Release configuration. They are a separate class, so that running `BenchmarkTests` alone measures what it did.
final class DocumentChangeBenchmarkTests: XCTestCase {
  /// The changes that each measurement makes, one in each frame.
  private static let frames = 120

  /// The elements of each group of the documents.
  private static let groupSize = 50

  override func setUpWithError() throws {
    guard ProcessInfo.processInfo.environment["RUN_BENCHMARKS"] == "1" else {
      throw XCTSkip("Set TEST_RUNNER_RUN_BENCHMARKS to 1 to measure the changes of documents.")
    }
  }

  /// The change that a measurement makes in every frame.
  private enum Change {
    /// Gives the view the data of a document in which one element has moved.
    case data
    /// Changes the `transform` attribute of one element, as dragging a shape does.
    case transform
    /// Changes the `d` attribute of one path, as dragging a control point of a curve does.
    case path
  }

  /// The identifiers of the elements that the measurements change: a rectangle and the path after it, in the middle
  /// of the document.
  private static func targets(count: Int) -> (rect: String, path: String) {
    let index = count / 2 / 2 * 2
    return ("e\(index)", "e\(index + 1)")
  }

  /// The data of a path whose control points are `offset` away from their places.
  private static func pathData(x: Int, y: Int, offset: Int = 0) -> String {
    "M\(x) \(y + 8)C\(x + 2) \(y - 4 + offset) \(x + 6) \(y + 20 - offset) \(x + 8) \(y + 8)"
  }

  /// A document of `count` elements, rectangles and curves in turn, in groups, with a style sheet.
  ///
  /// - Parameters:
  ///   - count: The number of the shapes.
  ///   - offset: How far the rectangle that the measurements change has moved.
  ///   - hasSiblingCombinators: Whether the style sheet has a rule with a sibling combinator, which makes a change of
  ///     an element compute the styles of the siblings after it again.
  private static func document(count: Int, offset: Int = 0, hasSiblingCombinators: Bool = false) -> Data {
    let columns = 50
    let target = targets(count: count).rect
    var text = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 \#((count + columns - 1) / columns * 20)">"#
    text += "<style>.a{stroke:#333;stroke-width:1}.b{fill:none;stroke:#c33}g>path{stroke-linecap:round}"
    if hasSiblingCombinators { text += "rect+path{stroke-width:2}" }
    text += "</style>"
    for index in 0..<count {
      if index % groupSize == 0 { text += #"<g class="g\#(index / groupSize)">"# }
      let x = index % columns * 20 + 4
      let y = index / columns * 20 + 2
      if index.isMultiple(of: 2) {
        let transform = "e\(index)" == target && offset != 0 ? #" transform="translate(\#(offset) 0)""# : ""
        text += #"<rect id="e\#(index)" class="a" x="\#(x)" y="\#(y)" width="12" height="12" fill="teal"\#(transform)/>"#
      } else {
        text += #"<path id="e\#(index)" class="b" d="\#(pathData(x: x, y: y))"/>"#
      }
      if index % groupSize == groupSize - 1 || index == count - 1 { text += "</g>" }
    }
    text += "</svg>"
    return Data(text.utf8)
  }

  /// The mean, the median, the 95th percentile and the largest of the durations, in milliseconds.
  private static func summary(of durations: [Duration]) -> String {
    let milliseconds = durations.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1e3 }
      .sorted()
    guard let last = milliseconds.last else { return "none" }
    return String(
      format: "mean %.3f ms, median %.3f ms, p95 %.3f ms, max %.3f ms",
      milliseconds.reduce(0, +) / Double(milliseconds.count), milliseconds[milliseconds.count / 2],
      milliseconds[milliseconds.count * 95 / 100], last)
  }

  /// Runs the main run loop until the condition holds, so that the renderings of the view, which finish on the main
  /// actor, can finish.
  @MainActor
  private func run(until condition: () -> Bool) {
    while !condition() {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }
  }

  /// Waits until the renderings that the view has started have finished.
  @MainActor
  private func waitForRendering(of view: SVGUIView) async {
    while let task = view.renderingTask {
      await task.value
      if view.renderingTask == task { break }
    }
  }

  /// Measures the frames of a view that shows a document of `count` elements, and makes a change in each frame.
  @MainActor
  private func measure(_ change: Change, count: Int, hasSiblingCombinators: Bool = false) throws {
    let window = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first)
    // The documents that giving the data alternates between: only the place of one rectangle differs.
    let documents = (0..<2).map {
      Self.document(count: count, offset: $0 * 4, hasSiblingCombinators: hasSiblingCombinators)
    }
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), data: documents[0])
    view.contentMode = .scaleAspectFit
    window.addSubview(view)
    defer { view.removeFromSuperview() }
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    run { !view.isRendering }

    let targets = Self.targets(count: count)
    let index = count / 2 / 2 * 2 + 1
    let (x, y) = (index % 50 * 20 + 4, index / 50 * 20 + 2)
    let clock = ContinuousClock()
    // How long each change kept the main thread, and how long its frame took, in all the iterations of the
    // measurement.
    var blocked: [Duration] = []
    var shown: [Duration] = []
    measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
      var isDone = false
      Task {
        for frame in 1...Self.frames {
          let start = clock.now
          switch change {
          case .data:
            view.data = documents[frame % 2]
          case .transform:
            view.document.element(id: targets.rect)?.setAttribute("transform", to: "translate(\(frame % 16) 0)")
          case .path:
            view.document.element(id: targets.path)?
              .setAttribute("d", to: Self.pathData(x: x, y: y, offset: frame % 16))
          }
          // Core Animation asks the view to display once in a frame: this starts the rendering as that does.
          view.layer.displayIfNeeded()
          blocked.append(clock.now - start)
          await waitForRendering(of: view)
          shown.append(clock.now - start)
        }
        isDone = true
      }
      run { isDone }
    }

    let report = String(
      format: "%d elements, %d bytes. Main thread per change: %@. Frame: %@", count, documents[0].count,
      Self.summary(of: blocked), Self.summary(of: shown))
    print("\(name) \(report)")
    let attachment = XCTAttachment(string: report)
    attachment.name = "Times per change"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor func testData100() throws { try measure(.data, count: 100) }
  @MainActor func testData500() throws { try measure(.data, count: 500) }
  @MainActor func testData2000() throws { try measure(.data, count: 2000) }
  @MainActor func testData5000() throws { try measure(.data, count: 5000) }
  @MainActor func testTransform100() throws { try measure(.transform, count: 100) }
  @MainActor func testTransform500() throws { try measure(.transform, count: 500) }
  @MainActor func testTransform2000() throws { try measure(.transform, count: 2000) }
  @MainActor func testTransform5000() throws { try measure(.transform, count: 5000) }
  @MainActor func testPath100() throws { try measure(.path, count: 100) }
  @MainActor func testPath500() throws { try measure(.path, count: 500) }
  @MainActor func testPath2000() throws { try measure(.path, count: 2000) }
  @MainActor func testPath5000() throws { try measure(.path, count: 5000) }
  @MainActor func testTransform2000WithSiblingCombinators() throws {
    try measure(.transform, count: 2000, hasSiblingCombinators: true)
  }
}
