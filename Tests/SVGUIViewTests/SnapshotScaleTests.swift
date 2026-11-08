import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a snapshot is rendered at a scale, and as a Core Graphics image.
@MainActor
@Suite("Snapshot scale")
struct SnapshotScaleTests {
  /// A document of 100 by 50 with a square that moves from left to right in 2 seconds.
  private static let svg = Data(
    #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">
      <rect width="50" height="50" fill="blue">
        <animate attributeName="x" from="0" to="50" dur="2s" fill="freeze"/>
      </rect>
    </svg>
    """#.utf8)

  private let rect = CGRect(x: 0, y: 0, width: 100, height: 50)

  /// A view of the document with a frame, which waits for its renderings as long as the other tests do, since the
  /// tests that fill the threads of the renderings can run at the same time.
  private func makeView(frame: CGRect) -> SVGUIView {
    let view = SVGUIView(frame: frame, data: Self.svg)
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    return view
  }

  @Test("the pixels of a snapshot are the rectangle times the scale", arguments: [1, 2, 3] as [CGFloat])
  func scale(scale: CGFloat) async throws {
    let view = makeView(frame: rect)
    let image = try #require(try await view.takeSnapshot(scale: scale).cgImage)
    #expect(image.width == Int(100 * scale))
    #expect(image.height == Int(50 * scale))
    let cgImage = try await view.takeCGImageSnapshot(scale: scale)
    #expect(cgImage.width == Int(100 * scale))
    #expect(cgImage.height == Int(50 * scale))
  }

  @Test("without a scale, a view that isn't on a screen renders a snapshot at the scale of the main screen")
  func defaultScale() async throws {
    let view = makeView(frame: rect)
    let image = try #require(try await view.takeSnapshot().cgImage)
    #expect(image.width == Int(100 * UIScreen.main.scale))
    #expect(try await view.takeCGImageSnapshot().height == Int(50 * UIScreen.main.scale))
  }

  @Test("without a scale, a snapshot is rendered at the display scale of the view's traits", arguments: [1, 2] as [CGFloat])
  func traitScale(scale: CGFloat) async throws {
    let view = makeView(frame: rect)
    view.traitOverrides.displayScale = scale
    view.updateTraitsIfNeeded()
    #expect(try await view.takeCGImageSnapshot().width == Int(100 * scale))
  }

  @Test("a view renders at the display scale of its traits", arguments: [1, 2] as [CGFloat])
  func renderingScale(scale: CGFloat) async throws {
    // A still document, which the view renders into one image.
    let view = SVGUIView(
      frame: rect,
      data: Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><rect width="50" height="50"/></svg>"#.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    view.traitOverrides.displayScale = scale
    view.updateTraitsIfNeeded()
    view.display(view.layer)
    try await waitUntil("The view doesn't show an image at the scale") {
      guard let contents = view.layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
        return false
      }
      return (contents as! CGImage).width == Int(100 * scale)
    }
  }

  @Test("a view without a frame renders into a rectangle that it's given, and throws without one")
  func viewWithoutFrame() async throws {
    let view = makeView(frame: .zero)
    let image = try await view.takeCGImageSnapshot(rect: rect, scale: 2)
    #expect(image.width == 200 && image.height == 100)
    await #expect(throws: SVGRenderingError.zeroSizedRect) {
      try await view.takeCGImageSnapshot(scale: 2)
    }
    await #expect(throws: SVGRenderingError.zeroSizedRect) {
      try await view.takeCGImageSnapshot(rect: rect, scale: 0)
    }
  }

  @Test("the Core Graphics image is the image of the snapshot at the same time")
  func sameImage() async throws {
    let view = makeView(frame: rect)
    let image = try #require(try await view.takeSnapshot(at: .seconds(1), scale: 2).cgImage)
    let cgImage = try await view.takeCGImageSnapshot(at: .seconds(1), scale: 2)
    #expect(cgImage.width == image.width && cgImage.height == image.height)
    #expect(try pixels(of: cgImage) == pixels(of: image))
    // The square has moved halfway at 1 second, so the image differs from the one at the start.
    let start = try await view.takeCGImageSnapshot(at: .zero, scale: 2)
    #expect(try pixels(of: cgImage) != pixels(of: start))
  }
}
