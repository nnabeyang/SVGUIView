import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// The motion of the element with the ID `r` at the time.
private func motion(_ content: String, at time: Double) throws -> CGAffineTransform {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return try #require(SVGParser.parse(data: Data(svg.utf8)).at(time: time)["r"]).style.motion
}

/// A rectangle with the ID `r` and the given animation elements.
private func rect(_ animations: String) -> String {
  #"<rect id="r" width="10" height="10">"# + animations + "</rect>"
}

/// Whether a transform moves the origin to the point and turns by the angle in degrees.
private func matches(_ transform: CGAffineTransform, _ x: Double, _ y: Double, angle: Double = 0) -> Bool {
  let turn = atan2(transform.b, transform.a) * 180 / .pi
  return abs(transform.tx - x) < 1e-6 && abs(transform.ty - y) < 1e-6 && abs(turn - angle) < 1e-6
}

@Suite("SMIL motion animations")
struct SMILMotionTests {
  /// Animations of motion, times, and the point and the angle that the element moves to then.
  private static let motions: [(String, Double, (x: Double, y: Double, angle: Double))] = [
    // A paced animation goes along the path by its length.
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" dur="4s"/>"#), 1, (10, 0, 0)),
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" dur="4s"/>"#), 3, (10, 20, 0)),
    // A linear animation takes the same time for each command of the path.
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" calcMode="linear" dur="4s"/>"#), 1, (5, 0, 0)),
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" calcMode="linear" dur="4s"/>"#), 3, (10, 15, 0)),
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" calcMode="discrete" dur="3s"/>"#), 1.5, (10, 0, 0)),
    // Key points are fractions of the length at the key times.
    (
      rect(#"<animateMotion path="M0 0 L40 0" calcMode="linear" keyPoints="0.5;1;0" keyTimes="0;0.5;1" dur="2s"/>"#),
      0.5, (30, 0, 0)
    ),
    // The values of a motion only make its path, so key times can fit its key points instead.
    (
      rect(
        #"<animateMotion values="0,0; 40,0" calcMode="linear" keyTimes="0;0.25;0.5;1" keyPoints="0;0.5;0.5;1" dur="4s"/>"#
      ), 1.5, (20, 0, 0)
    ),
    // Points of values, from, to and by.
    (rect(#"<animateMotion values="0,0; 20,0; 20,20" dur="2s"/>"#), 1.5, (20, 10, 0)),
    (rect(#"<animateMotion from="10,10" to="30,10" dur="2s"/>"#), 1, (20, 10, 0)),
    (rect(#"<animateMotion to="30,10" dur="2s"/>"#), 1, (15, 5, 0)),
    (rect(#"<animateMotion by="30 10" dur="2s"/>"#), 1, (15, 5, 0)),
    // rotate turns the element to the direction of the path, the opposite one, or an angle.
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" rotate="auto" dur="4s"/>"#), 3, (10, 20, 90)),
    (rect(#"<animateMotion path="M0 0 L10 0 L10 30" rotate="auto-reverse" dur="4s"/>"#), 3, (10, 20, -90)),
    (rect(#"<animateMotion path="M0 0 L10 0" rotate="30" dur="4s"/>"#), 2, (5, 0, 30)),
    // Each repeat of an accumulating animation starts where the previous one ended.
    (rect(#"<animateMotion path="M0 0 L10 0" dur="1s" repeatCount="3" accumulate="sum"/>"#), 2.5, (25, 0, 0)),
    // An additive animation moves from where the animation under it puts the element.
    (
      rect(
        #"<animateMotion path="M0 0 L0 20" dur="2s"/><animateMotion path="M0 0 L10 0" dur="2s" additive="sum"/>"#
      ), 1, (5, 10, 0)
    ),
    (
      rect(#"<animateMotion path="M0 0 L0 20" dur="2s"/><animateMotion path="M0 0 L10 0" dur="2s"/>"#), 1,
      (5, 0, 0)
    ),
  ]

  @Test("animateMotion moves the element along a path at a time", arguments: motions)
  func motionsAtTimes(content: String, time: Double, expected: (x: Double, y: Double, angle: Double)) throws {
    let transform = try motion(content, at: time)
    #expect(matches(transform, expected.x, expected.y, angle: expected.angle), "\(transform)")
  }

  @Test("mpath wins over path, which wins over values")
  func paths() throws {
    let content =
      ##"<path id="p" d="M0 50 L40 50" transform="scale(2)"/>"##
      + rect(
        ##"<animateMotion path="M0 0 L0 40" values="0,0; 40,40" dur="2s"><mpath href="#p"/></animateMotion>"##)
    #expect(matches(try motion(content, at: 1), 20, 50))
    #expect(matches(try motion(rect(#"<animateMotion path="M0 0 L0 40" values="0,0; 40,40" dur="2s"/>"#), at: 1), 0, 20))
  }

  @Test("an animation with values or key times that don't fit its path has no effect")
  func invalidMotions() throws {
    #expect(try motion(rect(#"<animateMotion values="0,0; 20" dur="2s"/>"#), at: 1) == .identity)
    #expect(
      try motion(rect(#"<animateMotion path="M0 0 L10 0" calcMode="linear" keyTimes="0;0.5;1" dur="2s"/>"#), at: 1)
        == .identity)
    #expect(
      try motion(rect(#"<animateMotion path="M0 0 L10 0" calcMode="linear" keyPoints="0;1" dur="2s"/>"#), at: 1)
        == .identity)
  }

  @Test("the motion applies after the transform of the element")
  func order() async throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <rect width="10" height="10" transform="scale(2)"><animateMotion from="0,0" to="10,0" dur="2s"/></rect>
      </svg>
      """#
    let base = SVGParser.parse(data: Data(svg.utf8)).at(time: 1)
    let builder = RenderTreeBuilder(base: base, viewPort: CGRect(x: 0, y: 0, width: 20, height: 20), scale: 1)
    let tree = try #require(
      await builder.build(
        fit: ContentFit(
          preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false,
          scales: true)))
    guard case .viewport(let viewport) = tree.root, case .shape(let shape) = viewport.content?.children.last else {
      Issue.record("The rectangle isn't a shape of the root")
      return
    }
    // The point (1, 0) is scaled to (2, 0), and then moved by 5.
    #expect(CGPoint(x: 1, y: 0).applying(shape.transform) == CGPoint(x: 7, y: 0))
  }
}
