import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app reads the length of a shape and the points along it, as the DOM's `getTotalLength()` and
/// `getPointAtLength()` find them.
@MainActor
@Suite("Path length", .serialized, .timeLimit(.minutes(2)))
struct PathLengthTests {
  private static let shapes = #"""
    <svg xmlns="http://www.w3.org/2000/svg">
    <path id="line" d="M 10 10 H 110 V 60" pathLength="10"/>
    <path id="curve" d="M 0 0 A 50 50 0 0 1 100 0"/>
    <path id="empty" d=""/>
    <rect id="rect" x="10" y="20" width="100" height="50"/>
    <rect id="rounded" x="0" y="0" width="100" height="50" rx="10"/>
    <circle id="circle" cx="50" cy="50" r="40"/>
    <circle id="dot" cx="50" cy="50" r="0"/>
    <rect id="flat" width="0" height="10"/>
    <path id="move" d="M 5 5"/>
    <ellipse id="ellipse" cx="50" cy="50" rx="40" ry="40"/>
    <line id="segment" x1="0" y1="0" x2="30" y2="40"/>
    <polyline id="polyline" points="0,0 10,0 10,10"/>
    <polygon id="polygon" points="0,0 10,0 10,10"/>
    <rect id="percent" width="50%" height="25%"/>
    <rect id="hidden" width="10" height="10" style="display: none"/>
    <defs><rect id="defined" width="20" height="10"/></defs>
    <g id="group"><rect width="10" height="10"/></g>
    <text id="text">A</text>
    </svg>
    """#

  private func view(_ content: String, size: CGSize = CGSize(width: 200, height: 100)) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(origin: .zero, size: size), data: Data(content.utf8))
    view.configuration = SVGUIViewConfiguration(animation: .none)
    return view
  }

  private func element(_ id: String, in view: SVGUIView) throws -> SVGDocument.Element {
    try #require(view.document.element(id: id))
  }

  @Test
  func lengths() throws {
    let view = view(Self.shapes)
    // The curves are measured as short lines along the Bézier curves that Core Graphics draws arcs with, so their
    // lengths differ a little from the ones of the arcs.
    let expected: [(id: String, length: CGFloat, accuracy: CGFloat)] = [
      // The `pathLength` doesn't scale the length.
      ("line", 150, 1e-9),
      ("curve", 50 * .pi, 0.05),
      ("empty", 0, 0),
      ("rect", 300, 1e-9),
      ("rounded", 220 + 20 * .pi, 0.05),
      ("circle", 80 * .pi, 0.05),
      ("dot", 0, 0),
      // A rectangle without an area has no path, as for Firefox, while Chrome measures it.
      ("flat", 0, 0),
      ("move", 0, 0),
      ("ellipse", 80 * .pi, 0.05),
      ("segment", 50, 1e-9),
      ("polyline", 20, 1e-9),
      ("polygon", 20 + 10 * 2.0.squareRoot(), 1e-9),
      // The percentages are of the size of the view.
      ("percent", 250, 1e-9),
      ("hidden", 40, 1e-9),
      ("defined", 60, 1e-9),
    ]
    for (id, length, accuracy) in expected {
      let found = try #require(try element(id, in: view).totalLength(), "\(id)")
      #expect(abs(found - length) <= accuracy, "\(id): \(found)")
    }
    for id in ["group", "text"] {
      #expect(try element(id, in: view).totalLength() == nil, "\(id)")
    }
  }

  @Test
  func points() throws {
    let view = view(Self.shapes)
    let line = try element("line", in: view)
    let expected: [(length: CGFloat, location: CGPoint, angle: CGFloat)] = [
      (0, CGPoint(x: 10, y: 10), 0),
      (50, CGPoint(x: 60, y: 10), 0),
      // At the corner, the direction is the one of the line before it.
      (100, CGPoint(x: 110, y: 10), 0),
      (125, CGPoint(x: 110, y: 35), .pi / 2),
      // The lengths outside the shape are clamped to it.
      (-5, CGPoint(x: 10, y: 10), 0),
      (500, CGPoint(x: 110, y: 60), .pi / 2),
    ]
    for (length, location, angle) in expected {
      let point = try #require(line.point(atLength: length))
      #expect(abs(point.location.x - location.x) < 1e-9 && abs(point.location.y - location.y) < 1e-9, "\(length)")
      #expect(abs(point.angle - angle) < 1e-9, "\(length)")
    }
    // A circle starts at the right of its center and goes clockwise, down the y-axis.
    let circle = try #require(try element("circle", in: view).point(atLength: 0))
    #expect(abs(circle.location.x - 90) < 1e-9 && abs(circle.location.y - 50) < 1e-9)
    #expect(abs(circle.angle - .pi / 2) < 0.05)
    // A rounded rectangle starts after its rounded corner.
    let rounded = try #require(try element("rounded", in: view).point(atLength: 0))
    #expect(rounded.location == CGPoint(x: 10, y: 0))
    // Shapes without a path have no point.
    #expect(try element("empty", in: view).point(atLength: 0) == nil)
    #expect(try element("dot", in: view).point(atLength: 0) == nil)
    #expect(try element("flat", in: view).point(atLength: 0) == nil)
    // A path with only a moveto has its point.
    #expect(try element("move", in: view).point(atLength: 1)?.location == CGPoint(x: 5, y: 5))
    #expect(try element("group", in: view).point(atLength: 0) == nil)
  }

  @Test
  func changes() throws {
    let view = view(Self.shapes)
    let rect = try element("rect", in: view)
    rect.setAttribute("width", to: "200")
    #expect(rect.totalLength() == 500)
    rect.style.setProperty("height", to: "10px")
    #expect(rect.totalLength() == 420)
    let created = view.document.createElement("line")
    created.setAttribute("x2", to: "10")
    // An element that isn't in the tree has no length.
    #expect(created.totalLength() == nil)
    try view.document.rootElement?.append(created)
    #expect(created.totalLength() == 10)
    created.remove()
    #expect(created.totalLength() == nil)
  }

  @Test
  func noView() throws {
    // The view that showed the document is gone, so the percentages have no viewport.
    let document = SVGUIView(data: Data(Self.shapes.utf8)).document
    #expect(try #require(document.element(id: "rect")).totalLength() == nil)
  }

  @Test
  func animatedLength() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 20, height: 20),
      data: Data(
        #"""
        <svg xmlns="http://www.w3.org/2000/svg"><style>@keyframes a { from { width: 0px } to { width: 20px } }
        rect { animation: a 2s linear }</style><rect id="r" width="10" height="10"/></svg>
        """#.utf8))
    view.clock = ManualClock()
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(animation: .play)
    window.addSubview(view)
    let rect = try #require(view.document.element(id: "r"))
    view.seek(to: .seconds(1))
    #expect(rect.totalLength() == 40)
  }
}
