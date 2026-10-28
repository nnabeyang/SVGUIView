import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

@Suite("Comparing the animated values of two times")
struct AnimatedValuesTests {
  /// Documents, two times, and whether their animated values are the same.
  private static let documents: [(String, Double, Double, Bool)] = [
    // No animations.
    (#"<rect width="10" height="10"/>"#, 0.1, 0.9, true),
    // The steps of an easing function change the values only at their edges.
    (
      "<style>@keyframes k { to { opacity: 0 } } rect { animation: k 1s steps(2, end) }</style>"
        + #"<rect width="10" height="10"/>"#, 0.1, 0.4, true
    ),
    (
      "<style>@keyframes k { to { opacity: 0 } } rect { animation: k 1s steps(2, end) }</style>"
        + #"<rect width="10" height="10"/>"#, 0.4, 0.6, false
    ),
    // A continuous animation changes them at every time, except before it starts.
    (
      "<style>@keyframes k { to { opacity: 0 } } rect { animation: k 1s linear }</style>"
        + #"<rect width="10" height="10"/>"#, 0.1, 0.2, false
    ),
    (
      "<style>@keyframes k { to { opacity: 0 } } rect { animation: k 1s linear 1s }</style>"
        + #"<rect width="10" height="10"/>"#, 0.1, 0.2, true
    ),
    // A `<set>` changes them where its interval begins and ends.
    (#"<rect width="10" height="10"><set attributeName="fill" to="red" begin="1s" dur="1s"/></rect>"#, 0.2, 0.5, true),
    (#"<rect width="10" height="10"><set attributeName="fill" to="red" begin="1s" dur="1s"/></rect>"#, 1.2, 1.5, true),
    (#"<rect width="10" height="10"><set attributeName="fill" to="red" begin="1s" dur="1s"/></rect>"#, 0.5, 1.2, false),
    // A discrete animation of an attribute that isn't a property.
    (
      #"<text x="0" y="10">a<animate attributeName="x" values="0;10" dur="1s" calcMode="discrete"/></text>"#, 0.1,
      0.4, true
    ),
    (
      #"<text x="0" y="10">a<animate attributeName="x" values="0;10" dur="1s" calcMode="discrete"/></text>"#, 0.4,
      0.6, false
    ),
    // A motion.
    (#"<rect width="10" height="10"><animateMotion path="M0,0 L10,0" dur="1s"/></rect>"#, 0.1, 0.2, false),
  ]

  @Test("whether two times of a document have the same animated values", arguments: documents)
  func sameValues(content: String, time: Double, otherTime: Double, expected: Bool) {
    let base = parse(content)
    #expect(base.at(time: time).hasSameAnimatedValues(as: base.at(time: otherTime)) == expected)
  }

  @Test("a transition changes the values while it runs")
  func transitions() throws {
    let base = parse(
      "<style>rect { transition: opacity 1s linear } .on { opacity: 0 }</style>" + #"<rect id="a" width="10" height="10"/>"#)
    let element = try #require(base.document.element(id: "a"))
    let changed = base.changingAttributes([element: ["class": "on"]], at: 0)
    #expect(!changed.at(time: 0.1).hasSameAnimatedValues(as: changed.at(time: 0.2)))
    #expect(changed.at(time: 1.1).hasSameAnimatedValues(as: changed.at(time: 1.2)))
  }
}
