import Foundation
import Testing

@testable import SVGCore

/// The end of the animations of a document with the content.
private func end(_ content: String) -> Double {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8)).animationEnd()
}

/// A rectangle that runs the CSS animations of a `@keyframes` rule named `a`.
private func css(_ animation: String) -> String {
  #"<style>@keyframes a { to { fill: lime } }</style><rect width="10" height="10" style="animation: "#
    + animation + #""/>"#
}

/// A rectangle with the SMIL animations.
private func smil(_ animations: String) -> String {
  #"<rect width="10" height="10">"# + animations + "</rect>"
}

@Suite("The end of the animations")
struct AnimationEndTests {
  /// Documents, and the times after which they don't change.
  private static let ends: [(String, Double)] = [
    (#"<rect width="10" height="10"/>"#, 0),
    // CSS Animations end after their delay and all their iterations.
    (css("a 1s"), 1),
    (css("a 1s 2s 3"), 5),
    (css("a 3s -1s"), 2),
    (css("a 1s -2s"), 0),
    (css("a 1s infinite"), .infinity),
    (css("a 0s 2s"), 2),
    (css("a 1s, a 2s 1s"), 3),
    // A paused animation stays at its start, and a name without a rule runs nothing.
    (css("a 1s paused"), 0),
    (css("b 1s"), 0),
    // SMIL animations end at the end of their last interval.
    (smil(#"<animate attributeName="fill" to="lime" begin="1s" dur="2s"/>"#), 3),
    (smil(#"<animate attributeName="fill" to="lime" dur="2s" repeatCount="indefinite"/>"#), .infinity),
    (smil(#"<animate attributeName="fill" to="lime" dur="2s" repeatCount="indefinite" end="5s"/>"#), 5),
    (smil(#"<animate attributeName="fill" to="lime" dur="1s" min="3s"/>"#), 3),
    (smil(#"<animate attributeName="fill" to="lime" begin="0s; 4s" dur="1s" fill="freeze"/>"#), 5),
    (
      smil(
        #"<animate id="x" attributeName="fill" to="lime" dur="1s"/><animate attributeName="x" to="5" begin="x.end+1s" dur="2s"/>"#
      ), 4
    ),
    (smil(#"<animate attributeName="fill" to="lime" begin="indefinite" dur="1s"/>"#), 0),
    // Animations that begin when the other one ends keep playing.
    (
      smil(
        #"<animate id="x" attributeName="fill" to="lime" begin="0s; y.end" dur="1s"/><animate id="y" attributeName="x" to="5" begin="x.end" dur="1s"/>"#
      ), .infinity
    ),
    // The document ends after both kinds of animations.
    (css("a 2s") + smil(#"<animate attributeName="x" to="5" dur="3s"/>"#), 3),
    (css("a 4s") + smil(#"<animate attributeName="x" to="5" dur="3s"/>"#), 4),
  ]

  @Test("the time after which the document doesn't change", arguments: ends)
  func animationEnds(content: String, expected: Double) {
    #expect(end(content) == expected)
  }
}
