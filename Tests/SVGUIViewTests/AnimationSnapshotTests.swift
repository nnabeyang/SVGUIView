import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that snapshots render documents with their animations at the given times.
@MainActor
@Suite("Snapshots of animations")
struct AnimationSnapshotTests {
  /// A document whose square changes from black to lime in one second, and stays lime.
  private static let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <style>@keyframes a { from { fill: rgb(0, 0, 0) } to { fill: rgb(0, 255, 0) } }</style>
      <rect width="20" height="20" fill="red" style="animation: a 1s linear forwards"/>
    </svg>
    """#

  /// The red, green, blue and alpha components of the pixel at the center of the document at the time.
  private func pixel(at time: Duration) async throws -> [UInt8] {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(Self.document.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
    let image = try #require(try await view.takeSnapshot(at: time).cgImage)
    var components = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image,
      in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    return components
  }

  @Test("a snapshot renders the document at the time of its animations")
  func snapshotsAtTimes() async throws {
    #expect(try await pixel(at: .zero) == [0, 0, 0, 255])
    let halfway = try await pixel(at: .milliseconds(500))
    #expect(halfway[0] == 0 && (127...128).contains(halfway[1]) && halfway[2] == 0 && halfway[3] == 255)
    #expect(try await pixel(at: .seconds(2)) == [0, 255, 0, 255])
  }
}
