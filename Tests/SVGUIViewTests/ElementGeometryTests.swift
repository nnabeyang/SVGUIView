import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("The geometry of elements")
struct ElementGeometryTests {
  /// A view, by default of 200 by 100, that shows a document of the content, by default in a view box of 200 by 100.
  private func view(
    _ content: String, root: String = #"viewBox="0 0 200 100""#, size: CGSize = CGSize(width: 200, height: 100)
  ) -> SVGUIView {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" \#(root)>"# + content + "</svg>"
    let view = SVGUIView(frame: CGRect(origin: .zero, size: size), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  private func element(_ id: String, in view: SVGUIView) throws -> SVGDocument.Element {
    try #require(view.document.element(id: id))
  }

  /// Whether two rectangles are the same but for rounding.
  private func isClose(_ a: CGRect?, _ b: CGRect, tolerance: CGFloat = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
      && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
  }

  private func isClose(_ a: CGAffineTransform?, _ b: CGAffineTransform) -> Bool {
    guard let a else { return false }
    return [a.a - b.a, a.b - b.b, a.c - b.c, a.d - b.d, a.tx - b.tx, a.ty - b.ty].allSatisfy { abs($0) < 1e-6 }
  }

  @Test("a shape has a bounding box without and with its stroke, without its dashes")
  func shapes() async throws {
    let view = view(
      #"<rect id="r" x="10" y="20" width="30" height="40" stroke="black" stroke-width="4" stroke-dasharray="1 9"/>"#
        + #"<circle id="c" cx="100" cy="50" r="10" stroke="black" stroke-width="2"/>"#)
    let rect = try element("r", in: view)
    #expect(isClose(await rect.boundingBox(), CGRect(x: 10, y: 20, width: 30, height: 40)))
    #expect(isClose(await rect.boundingBox(includingStroke: true), CGRect(x: 8, y: 18, width: 34, height: 44)))
    let circle = try element("c", in: view)
    #expect(isClose(await circle.boundingBox(), CGRect(x: 90, y: 40, width: 20, height: 20)))
    #expect(isClose(await circle.boundingBox(includingStroke: true), CGRect(x: 89, y: 39, width: 22, height: 22)))
  }

  @Test("the path of a shape is the path that it's filled with")
  func paths() async throws {
    let view = view(
      #"<path id="p" d="M 10 10 L 50 10 L 30 40 Z"/><rect id="r" x="60" y="10" width="20" height="10"/>"#)
    let path = try #require(try await element("p", in: view).path())
    #expect(isClose(path.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 40, height: 30)))
    #expect(path.contains(CGPoint(x: 30, y: 20)))
    #expect(!path.contains(CGPoint(x: 12, y: 35)))
    let rect = try #require(try await element("r", in: view).path())
    #expect(isClose(rect.boundingBoxOfPath, CGRect(x: 60, y: 10, width: 20, height: 10)))
    // A group has no shape.
    let group = self.view(#"<g id="g"><rect width="10" height="10"/></g>"#)
    #expect(try await element("g", in: group).path() == nil)
  }

  @Test("the bounding box of a group is the union of its children with their transforms, without its own transform")
  func groups() async throws {
    let view = view(
      #"<g id="g" transform="translate(100 0)">"#
        + #"<rect id="a" x="10" y="10" width="10" height="10"/>"#
        + #"<rect transform="translate(20 30)" x="10" y="10" width="10" height="10"/>"#
        + #"<rect display="none" x="-50" y="-50" width="10" height="10"/>"#
        + "</g>"
        + #"<g id="empty"/>"#)
    let group = try element("g", in: view)
    #expect(isClose(await group.boundingBox(), CGRect(x: 10, y: 10, width: 30, height: 40)))
    #expect(isClose(await group.transformToView(), CGAffineTransform(translationX: 100, y: 0)))
    // A child is in the user space of the group, which the transform of the group moves.
    #expect(isClose(try await element("a", in: view).transformToView(), CGAffineTransform(translationX: 100, y: 0)))
    #expect(isClose(try await element("empty", in: view).boundingBox(), .zero))
  }

  @Test("an element that isn't rendered has the bounding box that it would have")
  func notRendered() async throws {
    let view = view(
      #"<g display="none"><rect id="hidden" x="10" y="10" width="20" height="20"/></g>"#
        + #"<defs><rect id="defined" x="5" y="6" width="7" height="8"/></defs>"#
        + #"<rect id="none" display="none" x="1" y="2" width="3" height="4"/>"#)
    #expect(isClose(try await element("hidden", in: view).boundingBox(), CGRect(x: 10, y: 10, width: 20, height: 20)))
    #expect(isClose(try await element("defined", in: view).boundingBox(), CGRect(x: 5, y: 6, width: 7, height: 8)))
    #expect(isClose(try await element("none", in: view).boundingBox(), CGRect(x: 1, y: 2, width: 3, height: 4)))
    #expect(isClose(try await element("none", in: view).transformToView(), .identity))
  }

  @Test("an svg element has its bounding box in the coordinates of its content, which its view box places")
  func nestedViewport() async throws {
    let view = view(
      #"<svg id="inner" x="100" y="10" width="50" height="50" viewBox="0 0 10 10">"#
        + #"<rect id="r" x="2" y="2" width="4" height="4"/></svg>"#)
    let inner = try element("inner", in: view)
    #expect(isClose(await inner.boundingBox(), CGRect(x: 2, y: 2, width: 4, height: 4)))
    let toView = CGAffineTransform(a: 5, b: 0, c: 0, d: 5, tx: 100, ty: 10)
    #expect(isClose(await inner.transformToView(), toView))
    #expect(isClose(try await element("r", in: view).transformToView(), toView))
  }

  @Test("a transform about the fill box of the element turns it about its center")
  func fillBox() async throws {
    let view = view(
      #"<rect id="r" x="10" y="10" width="20" height="10" style="transform-box: fill-box; transform-origin: center; transform: rotate(90deg)"/>"#
    )
    let rect = try element("r", in: view)
    let box = try #require(await rect.boundingBox())
    let transform = try #require(await rect.transformToView())
    #expect(isClose(box.applying(transform), CGRect(x: 15, y: 5, width: 10, height: 20)))
  }

  @Test("a use element has the bounding box of what it references, moved by its x and y")
  func use() async throws {
    let view = view(
      #"<defs><rect id="shape" x="20" y="20" width="40" height="40"/></defs>"#
        + ##"<use id="u" href="#shape" x="10" y="10" transform="translate(5 0)"/>"##)
    let use = try element("u", in: view)
    #expect(isClose(await use.boundingBox(), CGRect(x: 30, y: 30, width: 40, height: 40)))
    #expect(isClose(await use.transformToView(), CGAffineTransform(translationX: 5, y: 0)))
    let path = try #require(await use.path())
    #expect(isClose(path.boundingBoxOfPath, CGRect(x: 30, y: 30, width: 40, height: 40)))
  }

  @Test("the bounding box of a text holds its glyphs, from the start of the text and across its line")
  func text() async throws {
    let view = view(#"<text id="t" x="10" y="50" font-size="20">Hello</text>"#)
    let text = try element("t", in: view)
    let box = try #require(await text.boundingBox())
    let glyphs = try #require(await text.path()).boundingBoxOfPath
    #expect(box.contains(glyphs))
    #expect(abs(box.minX - 10) < 1e-6)
    // The line extends above and below the baseline.
    #expect(box.minY < 50 - 10)
    #expect(box.maxY > 50)
  }

  @Test(
    "the transform to the view places the document as the content mode does",
    arguments: [
      (UIView.ContentMode.scaleAspectFit, CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 50)),
      (.scaleAspectFill, CGAffineTransform(a: 4, b: 0, c: 0, d: 4, tx: -100, ty: 0)),
      (.scaleToFill, CGAffineTransform(a: 2, b: 0, c: 0, d: 4, tx: 0, ty: 0)),
    ] as [(UIView.ContentMode, CGAffineTransform)])
  func contentMode(mode: UIView.ContentMode, transform: CGAffineTransform) async throws {
    // A document of 100 by 50 in a view of 200 by 200.
    let view = view(
      #"<rect id="r" width="10" height="10"/>"#, root: #"width="100" height="50""#,
      size: CGSize(width: 200, height: 200))
    view.contentMode = mode
    #expect(isClose(try await element("r", in: view).transformToView(), transform))
  }

  @Test("the geometry includes the changes made just before")
  func changes() async throws {
    let view = view(#"<rect id="r" width="10" height="10"/>"#)
    let rect = try element("r", in: view)
    rect.setAttribute("width", to: "50")
    rect.setAttribute("transform", to: "translate(7 0)")
    #expect(isClose(await rect.boundingBox(), CGRect(x: 0, y: 0, width: 50, height: 10)))
    #expect(isClose(await rect.transformToView(), CGAffineTransform(translationX: 7, y: 0)))
  }

  @Test("an element that the view doesn't show has no geometry")
  func notShown() async throws {
    let view = view(#"<rect id="r" width="10" height="10"/><mask id="m"><rect width="5" height="5"/></mask>"#)
    let created = view.document.createElement("rect")
    created.setAttribute("width", to: "10")
    #expect(await created.boundingBox() == nil)
    let rect = try element("r", in: view)
    rect.remove()
    #expect(await rect.boundingBox() == nil)
    // A mask isn't a graphics element.
    #expect(try await element("m", in: view).boundingBox() == nil)
    // The document that new data replaces isn't shown.
    let replaced = self.view(#"<rect id="r" width="10" height="10"/>"#)
    let old = try element("r", in: replaced)
    await replaced.setData(Data(document(#"<rect width="10" height="10"/>"#).utf8))
    #expect(await old.boundingBox() == nil)
  }
}
