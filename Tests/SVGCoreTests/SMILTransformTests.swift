import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// A document with the given content at the time.
private func document(_ content: String, at time: Double) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8)).at(time: time)
}

/// The transform functions of the element with the ID `r` at the time.
private func functions(_ content: String, at time: Double) throws -> [TransformFunction] {
  try #require(document(content, at: time)["r"]).style.transform.functions
}

/// A rectangle with the ID `r`, the given attributes and the given animation elements.
private func rect(_ attributes: String, _ animations: String) -> String {
  #"<rect id="r" width="10" height="10" "# + attributes + ">" + animations + "</rect>"
}

private func rect(_ animations: String) -> String {
  rect("", animations)
}

@Suite("SMIL transform animations")
struct SMILTransformTests {
  /// Animations of transforms, times, and the transform functions then.
  private static let transforms: [(String, Double, [TransformFunction])] = [
    // The type is translate without one, and each type fills in the numbers that a value leaves out.
    (
      rect(#"<animateTransform attributeName="transform" from="0 0" to="20 10" dur="2s"/>"#), 1,
      [.translate(.number(10), .number(5))]
    ),
    (
      rect(#"<animateTransform attributeName="transform" type="translate" from="0" to="20" dur="2s"/>"#), 1,
      [.translate(.number(10), .number(0))]
    ),
    (rect(#"<animateTransform attributeName="transform" type="scale" from="1" to="3" dur="2s"/>"#), 1, [.scale(2, 2)]),
    (
      rect(#"<animateTransform attributeName="transform" type="rotate" from="0" to="90" dur="2s"/>"#), 1,
      [.rotate(45)]
    ),
    (
      rect(#"<animateTransform attributeName="transform" type="rotate" from="0 5 5" to="90 5 5" dur="2s"/>"#), 1,
      [.translate(.number(5), .number(5)), .rotate(45), .translate(.number(-5), .number(-5))]
    ),
    (rect(#"<animateTransform attributeName="transform" type="skewX" to="30" dur="2s"/>"#), 1, [.skew(15, 0)]),
    (rect(#"<animateTransform attributeName="transform" type="skewY" to="30" dur="2s"/>"#), 1, [.skew(0, 15)]),
    // A replacing animation replaces the transform under it, and an additive one adds after it.
    (
      rect(
        #"transform="translate(5)""#, #"<animateTransform attributeName="transform" type="scale" from="1" to="3" dur="2s"/>"#
      ), 1, [.scale(2, 2)]
    ),
    (
      rect(
        #"transform="translate(5)""#,
        #"<animateTransform attributeName="transform" type="scale" from="1" to="3" dur="2s" additive="sum"/>"#), 1,
      [.translate(.number(5), .number(0)), .scale(2, 2)]
    ),
    // A by-animation is additive and starts from zero, also for scales.
    (
      rect(#"transform="translate(5)""#, #"<animateTransform attributeName="transform" type="scale" by="1" dur="2s"/>"#),
      1, [.translate(.number(5), .number(0)), .scale(0.5, 0.5)]
    ),
    // Values, a discrete calculation mode, paced values and accumulation.
    (
      rect(#"<animateTransform attributeName="transform" type="rotate" values="0;90;0" keyTimes="0;0.25;1" dur="4s"/>"#),
      2.5, [.rotate(45)]
    ),
    (
      rect(#"<animateTransform attributeName="transform" type="scale" values="1;2;3" calcMode="discrete" dur="3s"/>"#),
      1.5, [.scale(2, 2)]
    ),
    (
      rect(#"<animateTransform attributeName="transform" values="0;10;40" calcMode="paced" dur="4s"/>"#), 2,
      [.translate(.number(20), .number(0))]
    ),
    (
      rect(
        #"<animateTransform attributeName="transform" type="rotate" from="0" to="10" dur="1s" repeatCount="3" accumulate="sum"/>"#
      ), 2.5, [.rotate(25)]
    ),
    // Of two animations, the later one adds after the earlier one.
    (
      rect(
        #"<animateTransform attributeName="transform" type="scale" from="2" to="2" dur="2s"/><animateTransform attributeName="transform" type="rotate" from="10" to="10" dur="2s" additive="sum"/>"#
      ), 1, [.scale(2, 2), .rotate(10)]
    ),
    // A value that isn't valid for the type makes the animation have no effect.
    (
      rect(#"transform="rotate(5)""#, #"<animateTransform attributeName="transform" type="skewX" from="1 2" to="3 4" dur="2s"/>"#),
      1, [.rotate(5)]
    ),
    (rect(#"<animateTransform attributeName="transform" type="spin" from="1" to="3" dur="2s"/>"#), 1, []),
  ]

  @Test("animateTransform changes the transform at a time", arguments: transforms)
  func animatedTransforms(content: String, time: Double, expected: [TransformFunction]) throws {
    #expect(try functions(content, at: time) == expected)
  }

  @Test("CSS animations override animateTransform, and animate doesn't change transform")
  func cascade() throws {
    let css = "<style>@keyframes a { from { transform: rotate(30deg) } to { transform: rotate(30deg) } }</style>"
    let smil = #"<animateTransform attributeName="transform" type="scale" from="2" to="2" dur="2s"/>"#
    #expect(try functions(css + rect(#"style="animation: a 10s""#, smil), at: 1) == [.rotate(30)])
    #expect(
      try functions(rect(#"<animate attributeName="transform" from="scale(1)" to="scale(3)" dur="2s"/>"#), at: 1) == [])
  }

  @Test("animateTransform changes gradient and pattern transforms")
  func attributeTransforms() throws {
    let base = document(
      ##"""
      <linearGradient id="g" gradientTransform="translate(5)">
        <stop stop-color="lime"/>
        <animateTransform attributeName="gradientTransform" type="rotate" from="0" to="90" dur="2s" additive="sum"/>
      </linearGradient>
      <pattern id="p" width="1" height="1">
        <animateTransform attributeName="patternTransform" type="scale" from="1" to="3" dur="2s"/>
      </pattern>
      """##, at: 1)
    let gradient = try #require(base.pservers["g"] as? SVGLinearGradientServer)
    #expect(gradient.gradientTransform?.functions == [.translate(.number(5), .number(0)), .rotate(45)])
    #expect(try #require(base.patterns["p"]).patternTransform?.functions == [.scale(2, 2)])
  }
}
