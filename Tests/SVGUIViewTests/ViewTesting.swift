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

/// The document of the content in a user space of 20 by 20.
func document(_ content: String) -> String {
  #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
}

/// The pixels of an image, the red, green, blue and alpha components of each, premultiplied, row by row from the
/// top.
func pixels(of image: CGImage, sourceLocation: SourceLocation = #_sourceLocation) throws -> [UInt8] {
  var components = [UInt8](repeating: 0, count: image.width * image.height * 4)
  let context = try #require(
    CGContext(
      data: &components, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    sourceLocation: sourceLocation)
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return components
}

/// The snapshot of a document of 20 by 20, whose pixels are indexed from the top left.
struct Rendering {
  let components: [UInt8]
  let width: Int
  /// The pixels in a unit of the user space.
  let scale: Int

  /// The red, green, blue and alpha components of a pixel, premultiplied.
  func pixel(_ column: Int, _ row: Int) -> [UInt8] {
    let offset = (row * width + column) * 4
    return Array(components[offset..<(offset + 4)])
  }

  /// The components of the pixel at the top left of a point of the user space.
  func pixel(x: Int, y: Int) -> [UInt8] {
    pixel(x * scale, y * scale)
  }
}

/// The snapshot of a document that a view of 20 by 20 renders.
@MainActor
func render(svg: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> Rendering {
  let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
  view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
  let image = try #require(try await view.takeSnapshot().cgImage, sourceLocation: sourceLocation)
  return Rendering(
    components: try pixels(of: image, sourceLocation: sourceLocation), width: image.width,
    scale: image.width / 20)
}

/// The snapshot of the content in a user space of 20 by 20.
@MainActor
func render(_ content: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> Rendering {
  try await render(svg: document(content), sourceLocation: sourceLocation)
}

/// The red, green, blue and alpha components of a pixel of the content rendered in a user space of 20 by 20,
/// premultiplied.
@MainActor
func pixel(_ content: String, x: Int, y: Int, sourceLocation: SourceLocation = #_sourceLocation) async throws
  -> [UInt8]
{
  try await render(content, sourceLocation: sourceLocation).pixel(x: x, y: y)
}

/// The red, green, blue and alpha components of a pixel of a document that a view of 20 by 20 renders,
/// premultiplied.
@MainActor
func pixel(svg: String, x: Int, y: Int, sourceLocation: SourceLocation = #_sourceLocation) async throws -> [UInt8] {
  try await render(svg: svg, sourceLocation: sourceLocation).pixel(x: x, y: y)
}
