import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

private func clipPath(_ text: String, origin: DeclarationOrigin = .css) -> SVGClipPath? {
  ClipPathProperty.parse(text, origin: origin)
}

private func shape(_ text: String) throws -> BasicShape {
  guard case .shape(let shape?, _) = clipPath(text) else { throw ShapeError.notShape(text) }
  return shape
}

private enum ShapeError: Error {
  case notShape(String)
}

/// A context that resolves lengths without a font, in a viewport of 100 × 100.
private struct LengthContext: SVGLengthContext {
  var viewBoxSize: CGSize { CGSize(width: 100, height: 100) }
  var font: SVGUIFont? { nil }
  var textScale: Double { 1 }
  var rootFont: SVGUIFont? { nil }
  var viewPort: CGRect { CGRect(x: 0, y: 0, width: 100, height: 100) }
  var writingMode: WritingMode? { nil }
}

private func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
  abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001 && abs(a.maxX - b.maxX) < 0.001
    && abs(a.maxY - b.maxY) < 0.001
}

@Suite("Basic shapes of clip-path")
struct BasicShapeTests {
  @Test("clip-path reads a basic shape and a reference box in either order, with stroke-box by default")
  func references() {
    #expect(clipPath("url(#a)") == .url(url: "a"))
    #expect(clipPath("none") == SVGClipPath.none)
    #expect(clipPath("circle()") == .shape(.circle(radius: .closestSide, center: .center), box: .strokeBox))
    #expect(clipPath("fill-box circle()") == .shape(.circle(radius: .closestSide, center: .center), box: .fillBox))
    #expect(clipPath("circle() view-box") == .shape(.circle(radius: .closestSide, center: .center), box: .viewBox))
    #expect(clipPath("fill-box") == .shape(nil, box: .fillBox))
    // The boxes of CSS layout are the boxes of SVG elements.
    #expect(clipPath("content-box") == .shape(nil, box: .fillBox))
    #expect(clipPath("padding-box") == .shape(nil, box: .fillBox))
    #expect(clipPath("border-box") == .shape(nil, box: .strokeBox))
    #expect(clipPath("margin-box") == .shape(nil, box: .strokeBox))
    // A presentation attribute takes the same values.
    #expect(clipPath("circle(5 at 1 2)", origin: .attribute) == .shape(.circle(radius: .length(.number(5)), center: ShapePosition(x: .number(1), y: .number(2))), box: .strokeBox))
  }

  @Test(
    "invalid values of clip-path are dropped",
    arguments: [
      "circle(-5px)", "circle(5px 5px)", "circle(at)", "ellipse(5px)", "ellipse(-1px 2px)", "inset()",
      "inset(1px 2px 3px 4px 5px)", "inset(1px round -2px)", "inset(1px round)", "polygon()", "polygon(1px)",
      "polygon(1px 2px,)", "polygon(evenodd 1px 2px)", "rect(1px 2px 3px 4px)", "path('M0 0')", "circle() circle()",
      "fill-box stroke-box", "circle(5)",
    ])
  func invalid(text: String) {
    #expect(clipPath(text) == nil)
  }

  @Test("the arguments of basic shapes")
  func arguments() throws {
    #expect(
      try shape("circle(farthest-side at left 10px top 20%)")
        == .circle(radius: .farthestSide, center: ShapePosition(x: .pixel(10), y: .percent(20))))
    #expect(
      try shape("circle(50% at right top)")
        == .circle(radius: .length(.percent(50)), center: ShapePosition(x: .percent(100), y: .percent(0))))
    #expect(
      try shape("ellipse(10px closest-side at bottom)")
        == .ellipse(rx: .length(.pixel(10)), ry: .closestSide, center: ShapePosition(x: .percent(50), y: .percent(100))))
    let zero = ShapePosition(x: .number(0), y: .number(0))
    #expect(
      try shape("inset(1px 2px)")
        == .inset(InsetShape(top: .pixel(1), right: .pixel(2), bottom: .pixel(1), left: .pixel(2), radii: [zero, zero, zero, zero])))
    let radius = ShapePosition(x: .pixel(4), y: .pixel(5))
    #expect(
      try shape("inset(1px 2px 3px round 4px / 5px)")
        == .inset(InsetShape(top: .pixel(1), right: .pixel(2), bottom: .pixel(3), left: .pixel(2), radii: [radius, radius, radius, radius])))
    #expect(
      try shape("polygon(evenodd, 0 0, 10px 0, 10px 50%)")
        == .polygon(
          fillRule: .evenodd,
          points: [
            ShapePosition(x: .number(0), y: .number(0)), ShapePosition(x: .pixel(10), y: .number(0)),
            ShapePosition(x: .pixel(10), y: .percent(50)),
          ]))
  }

  @Test("an offset from the right or the bottom edge is a length from the left or the top")
  func offsetFromEnd() throws {
    let circle = try shape("circle(at right 10px bottom 20%)")
    let position: ShapePosition? = if case .circle(_, let center) = circle { center } else { nil }
    let center = try #require(position, "Not a circle")
    let point = center.point(in: CGRect(x: 0, y: 0, width: 200, height: 100), context: LengthContext())
    #expect(abs(point.x - 190) < 0.001 && abs(point.y - 80) < 0.001)
  }

  @Test(
    "a basic shape is a path in its reference box",
    arguments: [
      ("circle()", CGRect(x: 60, y: 0, width: 100, height: 100)),
      ("circle(farthest-side)", CGRect(x: 10, y: -50, width: 200, height: 200)),
      ("circle(50% at 0 0)", CGRect(x: 10 - 79.0569, y: -79.0569, width: 158.1139, height: 158.1139)),
      ("ellipse()", CGRect(x: 10, y: 0, width: 200, height: 100)),
      ("ellipse(25% 10% at 20px 30px)", CGRect(x: -20, y: 20, width: 100, height: 20)),
      ("inset(10% 20px)", CGRect(x: 30, y: 10, width: 160, height: 80)),
      // Insets that add up to more than the box are reduced in proportion.
      ("inset(0 150px 0 50px)", CGRect(x: 60, y: 0, width: 0.0001, height: 100)),
      ("polygon(0 0, 100% 50%, 50% 100%)", CGRect(x: 10, y: 0, width: 200, height: 100)),
    ])
  func paths(text: String, bounds: CGRect) throws {
    let clip = try #require(clipPath(text))
    let (path, _) = try #require(clip.shapePath(in: CGRect(x: 10, y: 0, width: 200, height: 100), context: LengthContext()))
    if bounds.width < 0.001 {
      #expect(path.isEmpty)
    } else {
      #expect(isClose(path.boundingBoxOfPath, bounds), "\(path.boundingBoxOfPath) isn't \(bounds)")
    }
  }

  @Test("the rounded corners of an inset are reduced when they overlap")
  func insetRadii() throws {
    let clip = try #require(clipPath("inset(0 round 75px 25px)"))
    let (path, _) = try #require(clip.shapePath(in: CGRect(x: 0, y: 0, width: 100, height: 100), context: LengthContext()))
    // The radii of the top side add up to 100, which is the width, so they aren't reduced: the corners are cut.
    #expect(!path.contains(CGPoint(x: 1, y: 1)))
    #expect(path.contains(CGPoint(x: 50, y: 50)))
    // Radii that add up to twice the side are halved, so the shape is still inside the box.
    let large = try #require(clipPath("inset(0 round 100px)"))
    let (circle, _) = try #require(large.shapePath(in: CGRect(x: 0, y: 0, width: 100, height: 100), context: LengthContext()))
    #expect(isClose(circle.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 100, height: 100)))
    #expect(!circle.contains(CGPoint(x: 10, y: 10)))
  }

  @Test("a polygon keeps its fill rule, and a reference box alone is the box")
  func fillRules() throws {
    let box = CGRect(x: 0, y: 0, width: 10, height: 10)
    #expect(try #require(clipPath("polygon(evenodd, 0 0, 1px 0, 1px 1px)")?.shapePath(in: box, context: LengthContext())).fillRule == .evenodd)
    #expect(try #require(clipPath("polygon(0 0, 1px 0, 1px 1px)")?.shapePath(in: box, context: LengthContext())).fillRule == .nonzero)
    #expect(try #require(clipPath("view-box")?.shapePath(in: box, context: LengthContext())).path.boundingBoxOfPath == box)
    #expect(SVGClipPath.url(url: "a").shapePath(in: box, context: LengthContext()) == nil)
  }

  @Test("shapes of the same kind with the same box are interpolated, and other values change discretely")
  func interpolation() throws {
    let resolver = StyleResolver(style: .initial, parent: .initial, root: .initial)
    let from = try #require(clipPath("circle(10px at 0 0)"))
    let to = try #require(clipPath("circle(20px at 10px 20px)"))
    #expect(ClipPathProperty.interpolates(from, to, in: resolver))
    #expect(
      ClipPathProperty.interpolated(from, to, progress: 0.5, in: resolver)
        == .shape(.circle(radius: .length(.pixel(15)), center: ShapePosition(x: .pixel(5), y: .pixel(10))), box: .strokeBox))
    let polygons = (try #require(clipPath("polygon(0 0, 10px 0, 0 10px)")), try #require(clipPath("polygon(10px 10px, 20px 0, 0 20px)")))
    #expect(ClipPathProperty.interpolates(polygons.0, polygons.1, in: resolver))
    let insets = (try #require(clipPath("inset(0 round 2px)")), try #require(clipPath("inset(10% round 4px)")))
    #expect(ClipPathProperty.interpolates(insets.0, insets.1, in: resolver))
    for (a, b) in [
      ("circle(10px)", "circle(10px) fill-box"), ("circle(10px)", "ellipse(10px 10px)"), ("circle()", "circle(10px)"),
      ("polygon(0 0, 1px 1px, 2px 0)", "polygon(evenodd, 0 0, 1px 1px, 2px 0)"),
      ("polygon(0 0, 1px 1px, 2px 0)", "polygon(0 0, 1px 1px)"), ("url(#a)", "url(#b)"), ("circle()", "none"),
    ] {
      let (from, to) = (try #require(clipPath(a)), try #require(clipPath(b)))
      #expect(!ClipPathProperty.interpolates(from, to, in: resolver), "\(a) and \(b)")
      #expect(ClipPathProperty.interpolated(from, to, progress: 0.4, in: resolver) == from)
    }
    // An overshoot doesn't make a radius negative.
    let radii = (try #require(clipPath("circle(10px)")), try #require(clipPath("circle(20px)")))
    #expect(
      ClipPathProperty.interpolated(radii.0, radii.1, progress: -2, in: resolver)
        == .shape(.circle(radius: .length(.pixel(0)), center: .center), box: .strokeBox))
    // SMIL animations change clip paths discretely.
    #expect(!ClipPathProperty.isInterpolable)
  }
}
