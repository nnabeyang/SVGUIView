import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// How long a test waits for a rendering, which only catches a rendering that never ends.
let patience: Duration = .seconds(60)

/// A clock that tests advance by hand.
@MainActor
final class ManualClock: AnimationClock {
  var onFrame: ((Duration) -> Void)?
  var isRunning = false

  /// Shows a frame after the time, if the clock is running.
  func advance(by time: Duration) {
    guard isRunning else { return }
    onFrame?(time)
  }
}

/// The green component of the pixel at the center of what the view shows, in its image or in its layers, or `nil`
/// if it shows nothing there.
@MainActor
func green(in view: SVGUIView) -> UInt8? {
  var components = [UInt8](repeating: 0, count: 4)
  guard
    let context = CGContext(
      data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }
  context.translateBy(x: -view.bounds.midX, y: -view.bounds.midY)
  view.layer.render(in: context)
  return components[3] == 0 ? nil : components[1]
}

/// Waits until the green component at the center of the image that the view shows passes the check.
@MainActor
func waitForGreen(
  in view: SVGUIView, sourceLocation: SourceLocation = #_sourceLocation, _ check: (UInt8) -> Bool
) async throws {
  let deadline = ContinuousClock.now + patience
  while green(in: view).map(check) != true {
    guard ContinuousClock.now < deadline else {
      Issue.record(
        "The view shows green \(green(in: view).map(String.init) ?? "nil")", sourceLocation: sourceLocation)
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}
