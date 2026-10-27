import SVGTestSuite
import UIKit
import XCTest

@testable import SVGUIView

/// Measures how long a view takes to render the frames of the documents in the `benchmark` folder of the test suite.
///
/// The times depend on the machine, so the tests run only when `TEST_RUNNER_RUN_BENCHMARKS` is `1`, and are skipped
/// in the snapshot tests and in CI. Devices give the times that matter: simulators don't reflect their performance.
/// Run them in the Release configuration, as apps are built, with `-configuration Release ENABLE_TESTABILITY=YES`:
/// the Debug configuration doesn't specialize the generic code of the styles, and takes many times longer.
final class BenchmarkTests: XCTestCase {
  /// The frames that each measurement renders, at 60 frames per second.
  private static let frames = 120

  override func setUpWithError() throws {
    guard ProcessInfo.processInfo.environment["RUN_BENCHMARKS"] == "1" else {
      throw XCTSkip("Set TEST_RUNNER_RUN_BENCHMARKS to 1 to measure the benchmark documents.")
    }
  }

  private func data(of name: String) throws -> Data {
    try Data(contentsOf: TestSuite.bundle.bundleURL.appending(path: "benchmark/\(name).svg"))
  }

  /// Runs the main run loop until the condition holds, so that the renderings of the view, which finish on the main
  /// actor, can finish.
  @MainActor
  private func run(until condition: () -> Bool) {
    while !condition() {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }
  }

  /// Measures the frames of a document played in layers, as a view that plays it renders them.
  @MainActor
  private func measureLayers(of name: String) throws {
    let window = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first)
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), data: try data(of: name))
    view.contentMode = .scaleAspectFit
    view.configuration = SVGUIViewConfiguration(animation: .paused)
    window.addSubview(view)
    defer { view.removeFromSuperview() }
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    run { !view.isRendering }
    // The time of each rendering, and of its stages.
    let stages = ["Render", "Style", "Build", "Plan", "Paint"].map {
      XCTOSSignpostMetric(subsystem: "com.github.nnabeyang.SVGUIView", category: "Rendering", name: $0)
    }
    measure(metrics: [XCTClockMetric()] + stages) {
      for frame in 1...Self.frames {
        view.seek(to: .seconds(Double(frame) / 60))
        run { !view.isRendering }
      }
    }
  }

  /// Measures the frames of a document rendered into one image each, as snapshots render them.
  @MainActor
  private func measureImages(of name: String) throws {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), data: try data(of: name))
    view.contentMode = .scaleAspectFit
    measure(metrics: [XCTClockMetric()]) {
      for frame in 1...Self.frames {
        var isDone = false
        Task {
          _ = try? await view.takeSnapshot(at: .seconds(Double(frame) / 60))
          isDone = true
        }
        run { isDone }
      }
    }
  }

  @MainActor func testTransformsInLayers() throws { try measureLayers(of: "transforms") }
  @MainActor func testTransformsInImages() throws { try measureImages(of: "transforms") }
  @MainActor func testPathsInLayers() throws { try measureLayers(of: "paths") }
  @MainActor func testPathsInImages() throws { try measureImages(of: "paths") }
  @MainActor func testManyElementsInLayers() throws { try measureLayers(of: "many-elements") }
  @MainActor func testManyElementsInImages() throws { try measureImages(of: "many-elements") }
  @MainActor func testFiltersInLayers() throws { try measureLayers(of: "filters") }
  @MainActor func testFiltersInImages() throws { try measureImages(of: "filters") }
}
