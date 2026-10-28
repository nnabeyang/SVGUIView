import Foundation
import Testing

@testable import SVGCore

/// A document whose rectangle the animation elements change.
private func parse(_ elements: String) -> SVGBaseContext {
  let svg =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect id="r" x="0" width="10" height="10">"#
    + elements + "</rect></svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The begins and ends of the intervals of each animation up to the time, with times that the document API begins
/// and ends the animations at.
private func intervals(
  _ elements: String, begins: [Double] = [], ends: [Double] = [], until time: Double = 100
) -> [[ClosedRange<Double>]] {
  var animations = parse(elements).animations.smil
  animations[0].addedBegins = begins
  animations[0].addedEnds = ends
  return SMILSchedule(animations: animations, until: time).intervals.map { $0.map { $0.begin...$0.end } }
}

/// The `x` of the rectangle at a time.
private func x(in base: SVGBaseContext, at time: Double) -> SVGLength? {
  base.at(time: time).root?.elements.first { $0.base.id == "r" }.flatMap { ($0 as? SVGRectElement)?.x }
}

@Suite("Beginning and ending SMIL animations from the document API")
struct SMILBeginEndTests {
  /// Animation elements, the times that the document API begins and ends the first one at, and the intervals of
  /// each animation.
  private static let schedules: [(String, [Double], [Double], [[ClosedRange<Double>]])] = [
    // Begin values that never come, and ones that do, take the times that the document API adds.
    (#"<set attributeName="x" to="5" begin="indefinite" dur="2s"/>"#, [3], [], [[3...5]]),
    (#"<set attributeName="x" to="5" begin="click" dur="2s"/>"#, [3, 7], [], [[3...5, 7...9]]),
    (#"<set attributeName="x" to="5" begin="1s" dur="2s"/>"#, [5], [], [[1...3, 5...7]]),
    // An end that the document API adds ends an interval early, with an `end` list or without one, and a begin after
    // it begins again.
    (#"<set attributeName="x" to="5" begin="indefinite" dur="4s"/>"#, [1, 6], [2], [[1...2, 6...10]]),
    (#"<set attributeName="x" to="5" dur="4s" end="10s"/>"#, [6], [2], [[0...2, 6...10]]),
    (#"<set attributeName="x" to="5" begin="indefinite"/>"#, [1], [3], [[1...3]]),
    // `restart` decides whether a begin in an interval begins it again.
    (#"<set attributeName="x" to="5" dur="4s" restart="whenNotActive"/>"#, [2, 5], [], [[0...4, 5...9]]),
    (#"<set attributeName="x" to="5" dur="4s" restart="always"/>"#, [2], [], [[0...2, 2...6]]),
    (#"<set attributeName="x" to="5" dur="4s" restart="never"/>"#, [5], [], [[0...4]]),
    // A syncbase value takes the times of the intervals that the document API begins.
    (
      #"<set id="a" attributeName="x" to="5" begin="indefinite" dur="1s"/>"#
        + #"<set attributeName="y" to="5" begin="a.end" dur="1s"/>"#, [2], [], [[2...3], [3...4]]
    ),
  ]

  @Test("the intervals with the times that the document API begins and ends an animation at", arguments: schedules)
  func schedule(elements: String, begins: [Double], ends: [Double], expected: [[ClosedRange<Double>]]) {
    #expect(intervals(elements, begins: begins, ends: ends) == expected)
  }

  @Test("a context begins and ends an animation at a time, which only animation elements are")
  func beginAndEnd() throws {
    let base = parse(#"<set id="s" attributeName="x" to="5" begin="indefinite" dur="2s"/>"#)
    let set = try #require(base.document.element(id: "s"))
    let rect = try #require(base.document.element(id: "r"))
    #expect(base.beginningSMILAnimation(rect, at: 1) == nil)
    #expect(base.endingSMILAnimation(rect, at: 1) == nil)
    #expect(base.animationEnd() == 0)
    let begun = try #require(base.beginningSMILAnimation(set, at: 3))
    #expect(x(in: begun, at: 2.9) == .number(0))
    #expect(x(in: begun, at: 3) == .number(5))
    #expect(begun.animationEnd() == 5)
    let ended = try #require(begun.endingSMILAnimation(set, at: 4))
    #expect(x(in: ended, at: 3.5) == .number(5))
    #expect(x(in: ended, at: 4) == .number(0))
    #expect(ended.animationEnd() == 4)
  }

  @Test("the times that the document API begins and ends an animation at stay when the document changes")
  func keepsTimes() throws {
    let base = parse(#"<set id="s" attributeName="x" to="5" begin="indefinite" dur="2s"/>"#)
    let set = try #require(base.document.element(id: "s"))
    let rect = try #require(base.document.element(id: "r"))
    let begun = try #require(base.beginningSMILAnimation(set, at: 3)?.endingSMILAnimation(set, at: 4))
    let changed = begun.changingAttributes([rect: ["fill": "lime"], set: ["dur": "3s"]], at: 6)
    let animation = try #require(changed.animations.smil.first)
    #expect(animation.addedBegins == [3])
    #expect(animation.addedEnds == [4])
  }
}
