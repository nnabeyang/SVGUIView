import Foundation
import Testing

@testable import SVGCore

/// A document whose rectangle `e` runs the animation `a`, which fades it in for 3 seconds, while it has the class
/// `spin`, with more content in the rectangle, such as SMIL animations.
private func document(_ content: String, class name: String = "") -> SVGBaseContext {
  let svg =
    #"<svg xmlns="http://www.w3.org/2000/svg"><style>@keyframes a { from { opacity: 0 } to { opacity: 1 } }"#
    + #" .spin { animation: a 3s linear }</style><rect id="e" width="10" height="10" class=""# + name + #"">"#
    + content + "</rect></svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// A document whose rectangle `e`, with more attributes, runs the animation `a`, which fades it in for 3 seconds, while
/// it matches the selector, with more content in the rectangle, such as SMIL animations.
private func document(_ content: String, selector: String, attributes: String = "") -> SVGBaseContext {
  let svg =
    #"<svg xmlns="http://www.w3.org/2000/svg"><style>@keyframes a { from { opacity: 0 } to { opacity: 1 } } "#
    + selector + #" { animation: a 3s linear }</style><rect id="e" width="10" height="10" "#
    + attributes + ">" + content + "</rect></svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The opacity of the rectangle at a time.
private func opacity(_ base: SVGBaseContext, at time: Double) throws -> Double {
  try #require(base.at(time: time)["e"]).style.opacity
}

@Suite("CSS animations that SMIL animations apply")
struct SMILStartedAnimationTests {
  /// A `<set>` that gives the rectangle the class `spin` from 2 seconds, for a second.
  private static let set = #"<set attributeName="class" to="spin" begin="2s" dur="1s" fill="freeze"/>"#

  @Test("an animation that a SMIL animation applies starts when it applies it, and ends after it")
  func startsWhenApplied() throws {
    let base = document(Self.set)
    #expect(abs(try opacity(base, at: 2.5) - 0.5 / 3) < 1e-9)
    #expect(base.animationEnd() == 5)
  }

  @Test("an animation that stops running before it ends doesn't keep the document changing")
  func stopsEarly() throws {
    let base = document(#"<set attributeName="class" to="spin" begin="2s" dur="1s"/>"#)
    #expect(abs(try opacity(base, at: 2.5) - 0.5 / 3) < 1e-9)
    #expect(try opacity(base, at: 3.5) == 1)
    #expect(base.animationEnd() == 3)
  }

  @Test("an animation that a SMIL animation applies again starts again")
  func startsAgain() throws {
    let base = document(
      #"<set attributeName="class" to="spin" begin="1s" dur="1s"/>"#
        + #"<set attributeName="class" to="spin" begin="4s" dur="1s" fill="freeze"/>"#)
    #expect(abs(try opacity(base, at: 1.5) - 0.5 / 3) < 1e-9)
    #expect(abs(try opacity(base, at: 4.5) - 0.5 / 3) < 1e-9)
    #expect(base.animationEnd() == 7)
  }

  @Test("an animation that a discrete value of an animate element applies starts when the value does")
  func discreteValues() throws {
    let base = document(#"<animate attributeName="class" values="x;spin" dur="2s" fill="freeze"/>"#)
    #expect(abs(try opacity(base, at: 1.5) - 0.5 / 3) < 1e-9)
    #expect(base.animationEnd() == 4)
  }

  @Test("an animation that the element runs as the document is loaded starts at time zero")
  func runsFromLoad() throws {
    let base = document(Self.set, class: "spin")
    #expect(abs(try opacity(base, at: 1) - 1.0 / 3) < 1e-9)
    #expect(abs(try opacity(base, at: 2.5) - 2.5 / 3) < 1e-9)
    #expect(base.animationEnd() == 3)
  }

  @Test("the playback that the document API gives an animation comes before the time that SMIL applies it")
  func documentPlayback() throws {
    let base = document(Self.set)
    let id = CSSAnimationID(element: try #require(base["e"]).base.elementID, name: "a", occurrence: 0)
    let played = base.settingPlayback(AnimationPlayback(startTime: 1), of: id)
    #expect(abs(try opacity(played, at: 2.5) - 1.5 / 3) < 1e-9)
  }

  @Test("animations that SMIL applies again and again keep the document changing")
  func applyForever() throws {
    let base = document(#"<animate attributeName="class" values="x;spin" dur="2s" repeatCount="indefinite"/>"#)
    #expect(base.animationEnd() == .infinity)
    #expect(abs(try opacity(base, at: 1.5) - 0.5 / 3) < 1e-9)
    #expect(abs(try opacity(base, at: 3.5) - 0.5 / 3) < 1e-9)
  }

  /// A `<set>` that gives the rectangle `pathLength="2"` from 2 seconds, for a second.
  private static let setPathLength = #"<set attributeName="pathLength" to="2" begin="2s" dur="1s" fill="freeze"/>"#

  @Test(
    "selectors other than class selectors see the attributes as written, not the values that SMIL animations give",
    arguments: [
      ("rect[pathLength]", "", Self.setPathLength),
      (#"rect[pathLength="2"]"#, #"pathLength="1""#, Self.setPathLength),
      (#"rect[class~="spin"]"#, "", Self.set),
      (":lang(en)", #"lang="fr""#, #"<set attributeName="lang" to="en" begin="2s" dur="1s" fill="freeze"/>"#),
    ])
  func writtenAttributes(selector: String, attributes: String, animation: String) throws {
    let base = document(animation, selector: selector, attributes: attributes)
    #expect(try opacity(base, at: 2.5) == 1)
    #expect(base.animations.smilStarted == SMILStartedAnimations())
  }

  @Test("an animation of a selector that matches the attribute as written runs from the start under SMIL animations")
  func writtenAttributeMatches() throws {
    let base = document(Self.setPathLength, selector: #"rect:not([pathLength="2"])"#, attributes: #"pathLength="1""#)
    #expect(abs(try opacity(base, at: 1) - 1.0 / 3) < 1e-9)
    #expect(abs(try opacity(base, at: 2.5) - 2.5 / 3) < 1e-9)
    #expect(base.animationEnd() == 3)
  }

  @Test("SMIL animations don't change the declarations of the style attribute")
  func styleAttribute() throws {
    let base = document(
      #"<set attributeName="style" to="opacity: 0.5" begin="0s" fill="freeze"/>"#, selector: ".none",
      attributes: #"style="opacity: 0.25""#)
    #expect(try opacity(base, at: 1) == 0.25)
  }

  @Test("an attribute that no selector matches doesn't make the elements again to find the animations that start")
  func unmatchedAttribute() throws {
    let base = document(Self.setPathLength, selector: ".spin")
    #expect(base.animations.smilStarted == SMILStartedAnimations())
    #expect(base.animationEnd() == 3)
  }
}
