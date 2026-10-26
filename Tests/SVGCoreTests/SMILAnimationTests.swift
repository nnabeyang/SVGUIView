import Foundation
import Testing

@testable import SVGCore

/// The computed values of the element with the ID `r` at the time.
private func style(_ content: String, at time: Double) throws -> ComputedStyle {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"# + content + "</svg>"
  return try #require(SVGParser.parse(data: Data(svg.utf8)).at(time: time)["r"]).style
}

/// A rectangle with the ID `r`, the given attributes and the given animation elements.
private func rect(_ attributes: String, _ animations: String) -> String {
  #"<rect id="r" width="10" height="10" "# + attributes + ">" + animations + "</rect>"
}

/// A rectangle with the ID `r` and the given animation elements.
private func rect(_ animations: String) -> String {
  rect("", animations)
}

private func isClose(_ a: Double, _ b: Double) -> Bool {
  abs(a - b) < 1e-9
}

@Suite("SMIL animations")
struct SMILAnimationTests {
  /// Rectangles with animations of `opacity`, times and the opacity then.
  private static let opacities: [(String, Double, Double)] = [
    (rect(#"<animate attributeName="opacity" from="0" to="1" dur="2s"/>"#), 0.5, 0.25),
    // A to-animation starts from the value under it, and a by-animation adds to it.
    (rect(#"opacity="0.2""#, #"<animate attributeName="opacity" to="1" dur="2s"/>"#), 1, 0.6),
    (rect(#"opacity="0.2""#, #"<animate attributeName="opacity" by="0.4" dur="2s"/>"#), 1, 0.4),
    (rect(#"opacity="0.2""#, #"<animate attributeName="opacity" from="0" by="0.5" dur="2s"/>"#), 1, 0.25),
    // Values and their times.
    (rect(#"<animate attributeName="opacity" values="0;1;0" keyTimes="0;0.25;1" dur="4s"/>"#), 1, 1),
    (rect(#"<animate attributeName="opacity" values="0;1;0" keyTimes="0;0.25;1" dur="4s"/>"#), 2.5, 0.5),
    (rect(#"<animate attributeName="opacity" values="0;0.5;1" calcMode="discrete" dur="3s"/>"#), 0.9, 0),
    (rect(#"<animate attributeName="opacity" values="0;0.5;1" calcMode="discrete" dur="3s"/>"#), 1.5, 0.5),
    (
      rect(#"<animate attributeName="opacity" values="0;0.5;1" calcMode="discrete" keyTimes="0;0.5;0.9" dur="1s"/>"#),
      0.95, 1
    ),
    // A paced animation spaces its values by their distances.
    (rect(#"<animate attributeName="opacity" values="0;0.2;1" calcMode="paced" dur="1s"/>"#), 0.5, 0.5),
    (rect(#"<animate attributeName="opacity" values="0;0.2;1" dur="1s"/>"#), 0.5, 0.2),
    // An additive animation adds to the value under it, and an accumulating one adds the last value of each repeat.
    (rect(#"opacity="0.2""#, #"<animate attributeName="opacity" from="0" to="0.4" dur="2s" additive="sum"/>"#), 1, 0.4),
    (
      rect(#"<animate attributeName="opacity" from="0" to="0.2" dur="1s" repeatCount="3" accumulate="sum"/>"#),
      2.5, 0.5
    ),
    // A to-animation doesn't add or accumulate.
    (
      rect(#"opacity="0.2""#, #"<animate attributeName="opacity" to="0.4" dur="2s" additive="sum" accumulate="sum"/>"#),
      1, 0.3
    ),
    // Without an effect, the value is the one under the animation.
    (rect(#"<animate attributeName="opacity" from="0" to="0.5" dur="1s" fill="freeze"/>"#), 3, 0.5),
    (rect(#"<animate attributeName="opacity" from="0" to="0.5" dur="1s"/>"#), 3, 1),
    (rect(#"<animate attributeName="opacity" from="0" to="0.5" begin="1s" dur="1s"/>"#), 0.5, 1),
    (rect(#"<set attributeName="opacity" to="0.3" begin="1s"/>"#), 2, 0.3),
    // A value that isn't valid for the property makes the animation have no effect.
    (rect(#"<animate attributeName="opacity" from="x" to="0.5" dur="1s"/>"#), 0.5, 1),
    // Of animations of the same property, the one whose interval began later wins, and the one later in the
    // document wins a tie.
    (rect(#"<set attributeName="opacity" to="0.3"/><set attributeName="opacity" to="0.6"/>"#), 1, 0.6),
    (
      rect(#"<set attributeName="opacity" to="0.3" begin="1s"/><set attributeName="opacity" to="0.6" begin="0.5s"/>"#),
      2, 0.3
    ),
    (
      rect(
        #"<set attributeName="opacity" to="0.5"/><animate attributeName="opacity" from="0" to="0.2" dur="1s" additive="sum"/>"#
      ),
      0.5, 0.6
    ),
  ]

  @Test("SMIL animations change properties at a time", arguments: opacities)
  func animatedOpacities(content: String, time: Double, opacity: Double) throws {
    let style = try style(content, at: time)
    #expect(isClose(style.opacity, opacity), "\(style.opacity)")
  }

  @Test("a spline changes the progress between values")
  func splines() throws {
    let style = try style(
      rect(#"<animate attributeName="opacity" values="0;1" calcMode="spline" keySplines="0.42 0 1 1" dur="1s"/>"#),
      at: 0.5)
    #expect(isClose(style.opacity, EasingFunction.cubicBezier(x1: 0.42, y1: 0, x2: 1, y2: 1)(0.5)))
  }

  @Test("keywords change discretely, even with a linear calculation mode")
  func keywords() throws {
    let content = rect(#"<animate attributeName="visibility" values="visible;hidden;visible" dur="3s"/>"#)
    #expect(try style(content, at: 0.9).visibility == .visible)
    #expect(try style(content, at: 1.5).visibility == .hidden)
    #expect(try style(content, at: 2.5).visibility == .visible)
  }

  @Test("CSS animations override SMIL animations, and important declarations override both")
  func cascade() throws {
    let css = "<style>@keyframes a { from { opacity: 0.4 } to { opacity: 0.4 } }</style>"
    let smil = #"<set attributeName="opacity" to="0.7"/>"#
    #expect(try style(css + rect(#"style="animation: a 10s""#, smil), at: 1).opacity == 0.4)
    #expect(try style(rect(#"style="opacity: 0.2 !important""#, smil), at: 1).opacity == 0.2)
    #expect(try style(rect(#"style="opacity: 0.2""#, smil), at: 1).opacity == 0.7)
  }

  @Test("inherit takes the value of the parent")
  func inherit() throws {
    let style = try style(#"<g opacity="0.5">"# + rect(#"<set attributeName="opacity" to="inherit"/>"#) + "</g>", at: 1)
    #expect(style.opacity == 0.5)
  }

  @Test("animate changes neither transform nor attributes that aren't properties of the element")
  func otherAttributes() throws {
    let style = try style(
      #"<circle id="r" r="5"><animate attributeName="transform" to="scale(2)" dur="1s"/><animate attributeName="x" to="5" dur="1s"/></circle>"#,
      at: 0.5)
    #expect(style.transform.functions.isEmpty)
    #expect(style.x == nil)
  }

  @Test("geometry properties of rectangles and colors are interpolated")
  func geometryAndColors() throws {
    let style = try style(
      rect(
        #"<animate attributeName="width" from="10" to="30" dur="2s"/><animate attributeName="fill" from="rgb(0, 0, 0)" to="rgb(0, 200, 0)" dur="2s"/>"#
      ), at: 1)
    #expect(style.width == .number(20))
    guard case .color(let fill) = style.fill else {
      Issue.record("The fill isn't a color")
      return
    }
    #expect(isClose(fill.components?.green ?? 0, 100.0 / 255))
  }
}
