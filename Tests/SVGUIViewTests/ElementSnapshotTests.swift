import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("Snapshots of elements")
struct ElementSnapshotTests {
  /// A view of 40 by 40 points that shows a document of 20 by 20.
  private func view(_ content: String) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40), data: Data(document(content).utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  private func element(_ id: String, in view: SVGUIView) throws -> SVGDocument.Element {
    try #require(view.document.element(id: id))
  }

  /// The largest difference between the components of the pixels of an image and of the snapshot of a view where
  /// the image is.
  private func difference(of snapshot: SVGDocument.ElementSnapshot, from view: SVGUIView, scale: CGFloat) async throws
    -> Int
  {
    let whole = try #require(try await view.takeSnapshot(scale: scale).cgImage)
    let rect = CGRect(
      x: snapshot.frame.minX * scale, y: snapshot.frame.minY * scale, width: snapshot.frame.width * scale,
      height: snapshot.frame.height * scale)
    let part = try #require(whole.cropping(to: rect))
    try #require(part.width == snapshot.image.width && part.height == snapshot.image.height)
    return zip(try pixels(of: part), try pixels(of: snapshot.image)).map { abs(Int($0) - Int($1)) }.max() ?? 0
  }

  @Test("the image covers the element on whole pixels with a margin, and has its pixels in the view")
  func shape() async throws {
    let view = view(#"<rect id="r" x="2" y="4" width="6" height="8" fill="red"/>"#)
    let snapshot = try #require(try await element("r", in: view).takeSnapshot(scale: 1))
    // The element is at (4, 8) to (16, 24) in the view, which shows the document at twice its size.
    #expect(snapshot.frame == CGRect(x: 2, y: 6, width: 16, height: 20))
    #expect(snapshot.image.width == 16 && snapshot.image.height == 20)
    #expect(try await difference(of: snapshot, from: view, scale: 1) == 0)
  }

  @Test("the scale sets the pixels of the image, and the frame lies on them")
  func scale() async throws {
    let view = view(#"<circle id="c" cx="10.3" cy="9.7" r="4.1" fill="blue"/>"#)
    let snapshot = try #require(try await element("c", in: view).takeSnapshot(scale: 3))
    #expect(CGFloat(snapshot.image.width) == snapshot.frame.width * 3)
    #expect(CGFloat(snapshot.image.height) == snapshot.frame.height * 3)
    #expect((snapshot.frame.minX * 3).rounded() == snapshot.frame.minX * 3)
    #expect(try await difference(of: snapshot, from: view, scale: 3) <= 2)
  }

  @Test("the image has the transforms of the element and of its ancestors, and its descendants")
  func transforms() async throws {
    let content =
      #"<g transform="translate(3 1)"><g id="g" transform="rotate(20 8 8)">"#
      + #"<rect x="4" y="4" width="6" height="6" fill="green"/><circle cx="12" cy="10" r="2" fill="orange"/>"#
      + "</g></g>"
    let view = view(content)
    let snapshot = try #require(try await element("g", in: view).takeSnapshot(scale: 2))
    #expect(try await difference(of: snapshot, from: view, scale: 2) <= 2)
    let box = try #require(await element("g", in: view).boundingBox())
    let transform = try #require(await element("g", in: view).transformToView())
    #expect(snapshot.frame.contains(box.applying(transform)))
  }

  @Test("the image has the opacity of the element, but not the other elements and the opacity of its ancestors")
  func elementAlone() async throws {
    let view = view(
      #"<rect width="20" height="20" fill="silver"/><g opacity="0.5">"#
        + #"<circle id="c" cx="10" cy="10" r="5" fill="purple" opacity="0.8"/></g>"#)
    let snapshot = try #require(try await element("c", in: view).takeSnapshot(scale: 2))
    let alone = self.view(#"<circle cx="10" cy="10" r="5" fill="purple" opacity="0.8"/>"#)
    #expect(try await difference(of: snapshot, from: alone, scale: 2) <= 1)
  }

  @Test("the image covers the filter region of the element")
  func filter() async throws {
    let view = view(
      #"<filter id="f"><feGaussianBlur stdDeviation="1"/></filter>"#
        + #"<rect id="r" x="6" y="6" width="8" height="8" fill="black" filter="url(#f)"/>"#)
    let snapshot = try #require(try await element("r", in: view).takeSnapshot(scale: 2))
    // The filter region is 10% larger on each side than the box, from (5.2, 5.2) to (14.8, 14.8), twice in the view.
    #expect(snapshot.frame.minX <= 10.4 && snapshot.frame.maxX >= 29.6)
    #expect(try await difference(of: snapshot, from: view, scale: 2) <= 2)
  }

  @Test("the image has the changes that the view hasn't rendered yet")
  func changes() async throws {
    let view = view(#"<rect id="r" x="5" y="5" width="10" height="10" fill="red"/>"#)
    let rect = try element("r", in: view)
    rect.setAttribute("fill", to: "blue")
    let snapshot = try #require(try await rect.takeSnapshot(scale: 1))
    let pixels = try pixels(of: snapshot.image)
    let center = ((snapshot.image.height / 2) * snapshot.image.width + snapshot.image.width / 2) * 4
    #expect(Array(pixels[center..<(center + 4)]) == [0, 0, 255, 255])
  }

  @Test(
    "an element that the view doesn't render, or that paints nothing, has no image",
    arguments: [
      #"<defs><rect id="e" width="5" height="5"/></defs>"#,
      #"<rect id="e" width="5" height="5" display="none"/>"#,
      #"<g display="none"><rect id="e" width="5" height="5"/></g>"#,
      #"<rect id="e" width="5" height="5" visibility="hidden"/>"#,
      #"<rect id="e" width="0" height="5"/>"#,
      #"<linearGradient id="e"/>"#,
    ])
  func noImage(content: String) async throws {
    let view = view(content)
    #expect(try await element("e", in: view).takeSnapshot() == nil)
  }

  @Test("an element outside the document's tree has no image")
  func removed() async throws {
    let view = view(#"<rect id="r" width="5" height="5"/>"#)
    let rect = try element("r", in: view)
    rect.remove()
    #expect(try await rect.takeSnapshot() == nil)
    #expect(try await view.document.createElement("rect").takeSnapshot() == nil)
  }
}
