import UIKit
import XCTest

@testable import SVGUIView

/// Measures how long a view takes to show a change of its document in every frame, as an app that edits shapes
/// makes while a finger drags one, for documents of several sizes.
///
/// The measurements compare the ways that an app has to change what a view shows: giving the view the data of
/// the changed document, changing an attribute of an element of the document of the view, inserting, removing
/// and moving elements of it, and changing the character data of a text and of the style sheet.
///
/// Besides the time and the time of the CPU of all the frames, and the time of the stages of the renderings, each test
/// reports, in the log and in an attachment, how long a change kept the main thread, from the change until the view
/// had started its rendering, and how long the whole frame took, until the view showed the change.
///
/// The continuous measurements change the document at every frame without waiting for the renderings, as dragging a
/// shape does, and report how many images the view showed, and how long after the changes that they show.
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
    /// Inserts a new shape after the shapes of a group in one frame and removes it in the next one, as drawing a
    /// shape and taking it back do.
    case insertion
    /// Moves one element after its siblings in one frame and back in the next one, as bringing a shape to the front
    /// and sending it back do.
    case order
    /// Changes the character data of a text after the shapes, as a counter that shows a value does.
    case text
    /// Changes the character data of the `<style>` element, which cascades every element again.
    case stylesheet
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
  ///   - hasLabel: Whether a text follows the shapes.
  private static func document(
    count: Int, offset: Int = 0, hasSiblingCombinators: Bool = false, hasLabel: Bool = false
  ) -> Data {
    let columns = 50
    let target = targets(count: count).rect
    var text = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 \#((count + columns - 1) / columns * 20)">"#
    text += #"<style id="style">"# + stylesheet
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
    if hasLabel { text += #"<text id="label" x="4" y="14" font-size="12">Frame 0</text>"# }
    text += "</svg>"
    return Data(text.utf8)
  }

  /// The rules of the style sheet of the documents.
  private static let stylesheet = ".a{stroke:#333;stroke-width:1}.b{fill:none;stroke:#c33}g>path{stroke-linecap:round}"

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

  /// A view in a window that shows a document of `count` elements, with what the changes of a measurement change.
  @MainActor
  private final class Scene {
    let view: SVGUIView
    /// The documents that giving the data alternates between: only the place of one rectangle differs.
    let documents: [Data]
    private let targets: (rect: String, path: String)
    /// The place of the path that the measurements change.
    private let x: Int
    private let y: Int
    /// The shape that the insertions insert and remove.
    private var inserted: SVGDocument.Element?

    init(_ change: Change, count: Int, hasSiblingCombinators: Bool) throws {
      let window = try XCTUnwrap(
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first)
      documents = (0..<2).map {
        DocumentChangeBenchmarkTests.document(
          count: count, offset: $0 * 4, hasSiblingCombinators: hasSiblingCombinators, hasLabel: change == .text)
      }
      view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), data: documents[0])
      view.contentMode = .scaleAspectFit
      window.addSubview(view)
      targets = DocumentChangeBenchmarkTests.targets(count: count)
      let index = count / 2 / 2 * 2 + 1
      (x, y) = (index % 50 * 20 + 4, index / 50 * 20 + 2)
    }

    /// Makes the change of a frame.
    func apply(_ change: Change, frame: Int) {
      switch change {
      case .data:
        view.data = documents[frame % 2]
      case .transform:
        view.document.element(id: targets.rect)?.setAttribute("transform", to: "translate(\(frame % 16) 0)")
      case .path:
        view.document.element(id: targets.path)?
          .setAttribute("d", to: DocumentChangeBenchmarkTests.pathData(x: x, y: y, offset: frame % 16))
      case .insertion:
        if let shape = inserted {
          shape.remove()
          inserted = nil
        } else {
          let shape = view.document.createElement("rect")
          shape.setAttribute("x", to: "\(x)")
          shape.setAttribute("y", to: "\(y)")
          shape.setAttribute("width", to: "12")
          shape.setAttribute("height", to: "12")
          try? view.document.element(id: targets.rect)?.parent?.append(shape)
          inserted = shape
        }
      case .order:
        if let rect = view.document.element(id: targets.rect), let parent = rect.parent {
          let path = view.document.element(id: targets.path)
          try? parent.insert(rect, before: frame % 2 == 1 ? nil : path)
        }
      case .text:
        view.document.element(id: "label")?.textContent = "Frame \(frame)"
      case .stylesheet:
        view.document.element(id: "style")?.textContent =
          DocumentChangeBenchmarkTests.stylesheet + (frame.isMultiple(of: 2) ? "" : ".a{stroke-width:2}")
      }
    }
  }

  /// The metrics of the measurements: the time and the time of the CPU of all the frames, and the time of the stages
  /// of the renderings, which tells which stage a change makes longer.
  private static var metrics: [any XCTMetric] {
    [XCTClockMetric(), XCTCPUMetric()]
      + ["Style", "Build", "Paint"].map {
        XCTOSSignpostMetric(subsystem: "com.github.nnabeyang.SVGUIView", category: "Rendering", name: $0)
      }
  }

  /// Shows the scene's first rendering, and returns the scene.
  @MainActor
  private func makeScene(_ change: Change, count: Int, hasSiblingCombinators: Bool) throws -> Scene {
    let scene = try Scene(change, count: count, hasSiblingCombinators: hasSiblingCombinators)
    scene.view.layoutIfNeeded()
    scene.view.layer.displayIfNeeded()
    run { !scene.view.isRendering }
    return scene
  }

  /// Attaches the report of a measurement, and prints it.
  private func report(_ report: String) {
    print("\(name) \(report)")
    let attachment = XCTAttachment(string: report)
    attachment.name = "Times per change"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Measures the frames of a view that shows a document of `count` elements, and makes a change in each frame.
  @MainActor
  private func measure(_ change: Change, count: Int, hasSiblingCombinators: Bool = false) throws {
    let scene = try makeScene(change, count: count, hasSiblingCombinators: hasSiblingCombinators)
    let view = scene.view
    defer { view.removeFromSuperview() }
    let clock = ContinuousClock()
    // How long each change kept the main thread, and how long its frame took, in all the iterations of the
    // measurement.
    var blocked: [Duration] = []
    var shown: [Duration] = []
    measure(metrics: Self.metrics) {
      var isDone = false
      Task {
        for frame in 1...Self.frames {
          let start = clock.now
          scene.apply(change, frame: frame)
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

    report(
      String(
        format: "%d elements, %d bytes. Main thread per change: %@. Frame: %@", count, scene.documents[0].count,
        Self.summary(of: blocked), Self.summary(of: shown)))
  }

  /// Measures a view that shows a document of `count` elements, and makes a change at every frame of 60 Hz without
  /// waiting for the renderings, as dragging a shape makes them.
  ///
  /// It reports how many of the changes the view showed images for, and how long after the latest change that an
  /// image shows the view showed it.
  @MainActor
  private func measureContinuous(_ change: Change, count: Int) throws {
    let scene = try makeScene(change, count: count, hasSiblingCombinators: false)
    let view = scene.view
    defer { view.removeFromSuperview() }
    let clock = ContinuousClock()
    let interval = Duration.seconds(1) / 60
    var shownImages: [Int] = []
    var latencies: [Duration] = []
    measure(metrics: Self.metrics) {
      // The time of the latest change that each rendering shows, by the generation of the rendering.
      var changeTimes: [Int: ContinuousClock.Instant] = [:]
      var generation = view.renderingGeneration
      var contents = view.layer.contents as AnyObject?
      var latestChange = clock.now
      var images = 0
      var frame = 0
      let start = clock.now
      while frame < Self.frames || view.isRendering || view.layer.needsDisplay() {
        let now = clock.now
        if frame < Self.frames, now >= start + interval * frame {
          frame += 1
          scene.apply(change, frame: frame)
          latestChange = now
          view.layer.displayIfNeeded()
        }
        // A rendering that starts now, here or when the one before it finishes, shows the changes until now.
        while generation < view.renderingGeneration {
          generation += 1
          changeTimes[generation] = latestChange
        }
        if let shown = view.layer.contents as AnyObject?, shown !== contents {
          contents = shown
          images += 1
          // The view starts the next rendering when it shows one, if the document changed meanwhile.
          let shownGeneration = view.isRendering ? view.renderingGeneration - 1 : view.renderingGeneration
          if let time = changeTimes[shownGeneration] {
            latencies.append(clock.now - time)
          }
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
      }
      shownImages.append(images)
    }

    report(
      String(
        format: "%d elements, %d bytes. Images shown for %d changes: %@. From the latest change to its image: %@",
        count, scene.documents[0].count, Self.frames,
        shownImages.map(String.init).joined(separator: ", "), Self.summary(of: latencies)))
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
  @MainActor func testInsertion100() throws { try measure(.insertion, count: 100) }
  @MainActor func testInsertion500() throws { try measure(.insertion, count: 500) }
  @MainActor func testInsertion2000() throws { try measure(.insertion, count: 2000) }
  @MainActor func testInsertion5000() throws { try measure(.insertion, count: 5000) }
  @MainActor func testOrder100() throws { try measure(.order, count: 100) }
  @MainActor func testOrder500() throws { try measure(.order, count: 500) }
  @MainActor func testOrder2000() throws { try measure(.order, count: 2000) }
  @MainActor func testOrder5000() throws { try measure(.order, count: 5000) }
  @MainActor func testText100() throws { try measure(.text, count: 100) }
  @MainActor func testText500() throws { try measure(.text, count: 500) }
  @MainActor func testText2000() throws { try measure(.text, count: 2000) }
  @MainActor func testText5000() throws { try measure(.text, count: 5000) }
  @MainActor func testStylesheet500() throws { try measure(.stylesheet, count: 500) }
  @MainActor func testStylesheet2000() throws { try measure(.stylesheet, count: 2000) }
  @MainActor func testInsertion2000WithSiblingCombinators() throws {
    try measure(.insertion, count: 2000, hasSiblingCombinators: true)
  }
  @MainActor func testTransform2000WithSiblingCombinators() throws {
    try measure(.transform, count: 2000, hasSiblingCombinators: true)
  }
  @MainActor func testContinuousTransform500() throws { try measureContinuous(.transform, count: 500) }
  @MainActor func testContinuousTransform2000() throws { try measureContinuous(.transform, count: 2000) }
  @MainActor func testContinuousTransform5000() throws { try measureContinuous(.transform, count: 5000) }
  @MainActor func testContinuousPath2000() throws { try measureContinuous(.path, count: 2000) }
}
