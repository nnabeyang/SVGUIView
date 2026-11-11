import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a content mode places the box of the width and the height of the root element in the bounds of the
/// view, and that the root element places its view box in that box.
@MainActor
@Suite("Content mode")
struct ContentModeTests {
  /// A document whose view box of 10 by 10 is filled, with a width and a height.
  private static func svg(width: Int, height: Int) -> Data {
    Data(
      """
      <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 10 10">
        <rect width="10" height="10" fill="blue"/>
      </svg>
      """.utf8)
  }

  /// The pixels that a view of a size paints for a document of a size, as ranges of x and y.
  struct Placement: Sendable, CustomTestStringConvertible {
    let document: (width: Int, height: Int)
    let view: (width: Int, height: Int)
    let contentMode: UIView.ContentMode
    let name: String
    let x: ClosedRange<Int>
    let y: ClosedRange<Int>

    var testDescription: String {
      "\(name), a document of \(document.width) by \(document.height) in a view of \(view.width) by \(view.height)"
    }

    init(
      _ name: String, _ contentMode: UIView.ContentMode, document: (Int, Int), view: (Int, Int), x: ClosedRange<Int>,
      y: ClosedRange<Int>
    ) {
      self.name = name
      self.contentMode = contentMode
      self.document = document
      self.view = view
      self.x = x
      self.y = y
    }
  }

  nonisolated private static let placements: [Placement] = [
    // A square document, whose view box is smaller than its width and height.
    Placement("scaleToFill", .scaleToFill, document: (100, 100), view: (100, 100), x: 0...99, y: 0...99),
    Placement("scaleToFill", .scaleToFill, document: (100, 100), view: (300, 300), x: 0...299, y: 0...299),
    Placement("scaleToFill", .scaleToFill, document: (1000, 1000), view: (300, 300), x: 0...299, y: 0...299),
    Placement("scaleToFill", .scaleToFill, document: (100, 100), view: (300, 150), x: 0...299, y: 0...149),
    Placement("scaleAspectFit", .scaleAspectFit, document: (100, 100), view: (300, 150), x: 75...224, y: 0...149),
    Placement("scaleAspectFill", .scaleAspectFill, document: (100, 100), view: (300, 150), x: 0...299, y: 0...149),
    Placement("redraw", .redraw, document: (100, 100), view: (300, 150), x: 0...299, y: 0...149),
    Placement("center", .center, document: (100, 100), view: (100, 100), x: 0...99, y: 0...99),
    Placement("center", .center, document: (100, 100), view: (300, 150), x: 100...199, y: 25...124),
    Placement("bottomRight", .bottomRight, document: (100, 100), view: (300, 150), x: 200...299, y: 50...149),
    // A wide document, which places its view box in the middle of its box.
    Placement("scaleToFill", .scaleToFill, document: (40, 20), view: (40, 20), x: 10...29, y: 0...19),
    Placement("scaleAspectFit", .scaleAspectFit, document: (40, 20), view: (40, 20), x: 10...29, y: 0...19),
    Placement("scaleAspectFill", .scaleAspectFill, document: (40, 20), view: (40, 20), x: 10...29, y: 0...19),
    Placement("redraw", .redraw, document: (40, 20), view: (40, 20), x: 10...29, y: 0...19),
    Placement("center", .center, document: (40, 20), view: (40, 20), x: 10...29, y: 0...19),
    Placement("topLeft", .topLeft, document: (40, 20), view: (40, 20), x: 10...29, y: 0...19),
    Placement("scaleToFill", .scaleToFill, document: (40, 20), view: (300, 300), x: 75...224, y: 0...299),
    Placement("scaleAspectFit", .scaleAspectFit, document: (40, 20), view: (300, 300), x: 75...224, y: 75...224),
    Placement("scaleAspectFill", .scaleAspectFill, document: (40, 20), view: (300, 300), x: 0...299, y: 0...299),
    Placement("scaleAspectFit", .scaleAspectFit, document: (400, 200), view: (400, 200), x: 100...299, y: 0...199),
    Placement("center", .center, document: (40, 20), view: (300, 300), x: 140...159, y: 140...159),
    // A tall document.
    Placement("scaleToFill", .scaleToFill, document: (20, 40), view: (300, 300), x: 0...299, y: 75...224),
    Placement("scaleAspectFit", .scaleAspectFit, document: (20, 40), view: (20, 40), x: 0...19, y: 10...29),
    Placement("scaleAspectFit", .scaleAspectFit, document: (20, 40), view: (300, 300), x: 75...224, y: 75...224),
    Placement("topLeft", .topLeft, document: (20, 40), view: (20, 40), x: 0...19, y: 10...29),
  ]

  /// The ranges of x and y of the pixels of the image that are opaque, or `nil` if none is.
  private func paintedRanges(of image: CGImage) throws -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
    let width = image.width
    let height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var (minX, minY, maxX, maxY) = (width, height, -1, -1)
    for y in 0..<height {
      for x in 0..<width where data[(y * width + x) * 4 + 3] > 127 {
        minX = min(minX, x)
        maxX = max(maxX, x)
        // The first row of the bitmap is the top of the image.
        minY = min(minY, y)
        maxY = max(maxY, y)
      }
    }
    return maxX < 0 ? nil : (minX...maxX, minY...maxY)
  }

  @Test("a content mode places the width and the height of the document, not its view box", arguments: placements)
  func placement(_ placement: Placement) async throws {
    let frame = CGRect(x: 0, y: 0, width: placement.view.width, height: placement.view.height)
    let view = SVGUIView(
      frame: frame, data: Self.svg(width: placement.document.width, height: placement.document.height))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    view.contentMode = placement.contentMode
    let image = try await view.takeCGImageSnapshot(rect: frame, scale: 1)
    let ranges = try #require(try paintedRanges(of: image))
    #expect(ranges.x == placement.x)
    #expect(ranges.y == placement.y)
  }
}
