import Foundation
import Testing

@testable import SVGCore

/// The SMIL animations of a document with the given animation elements, which change a rectangle.
private func animations(_ elements: String) -> [SMILAnimation] {
  let svg =
    #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="10" height="10">"# + elements
    + "</rect></svg>"
  return SVGParser.parse(data: Data(svg.utf8)).animations.smil
}

/// The animation of a `<set>` element with the given timing attributes.
private func animation(_ attributes: String) throws -> SMILAnimation {
  try #require(animations(#"<set attributeName="x" to="5" "# + attributes + "/>").first)
}

/// The begins and ends of the intervals of each animation, up to the time.
private func intervals(_ elements: String, until time: Double) -> [[ClosedRange<Double>]] {
  SMILSchedule(animations: animations(elements), until: time).intervals.map { $0.map { $0.begin...$0.end } }
}

@Suite("SMIL timing")
struct SMILTimingTests {
  /// Timing attributes, and the active duration and the duration that plays the simple duration, of an interval
  /// that begins at 1 second.
  private static let durations: [(String, Double, Double)] = [
    (#"dur="2s""#, 2, 2),
    (#""#, .infinity, .infinity),
    (#"dur="2s" repeatCount="2.5""#, 5, 5),
    (#"dur="2s" repeatCount="indefinite""#, .infinity, .infinity),
    (#"dur="2s" repeatDur="3s""#, 3, 3),
    (#"dur="2s" repeatCount="3" repeatDur="5s""#, 5, 5),
    (#"dur="2s" repeatCount="2" repeatDur="5s""#, 4, 4),
    (#"repeatDur="3s""#, 3, 3),
    (#"repeatCount="3""#, .infinity, .infinity),
    // An end time cuts the active duration, which is the whole time to the end without a duration.
    (#"dur="2s" repeatCount="3" end="4s""#, 3, 3),
    (#"end="4s""#, 3, 3),
    (#"dur="2s" end="9s""#, 2, 2),
    // `max` cuts the active duration, and `min` makes it longer, with the time after the repeats filled.
    (#"dur="2s" repeatCount="3" max="5s""#, 5, 5),
    (#"dur="1s" repeatCount="5" end="3s" min="8s""#, 8, 5),
    (#"dur="indefinite" end="3s" min="5s""#, 5, 5),
    (#"dur="2s" min="1s""#, 2, 2),
    (#"min="2s" max="5s""#, 5, 5),
  ]

  @Test("the active duration of an interval", arguments: durations)
  func activeDurations(attributes: String, active: Double, played: Double) throws {
    let animation = try animation(attributes)
    let end = animation.end.flatMap { values -> Double? in
      if case .offset(let time) = values.first { time } else { nil }
    }
    let duration = SMILSchedule.activeDuration(of: animation, from: 1, to: end)
    #expect(duration.active == active)
    #expect(duration.played == played)
  }

  /// Timing attributes, and the begins and the ends of the intervals up to 10 seconds.
  private static let intervalLists: [(String, [ClosedRange<Double>])] = [
    (#"dur="2s""#, [0...2]),
    (#"begin="1s; 5s" dur="2s""#, [1...3, 5...7]),
    (#"begin="5s; 1s" dur="2s""#, [1...3, 5...7]),
    (#"begin="-1s" dur="2s""#, [-1...1]),
    // An interval that ends before the document begins doesn't count.
    (#"begin="-3s; 4s" dur="2s""#, [4...6]),
    (#"begin="0s; 2s; 4s" end="1s; 3s""#, [0...1, 2...3]),
    // A begin time in an interval restarts it, unless `restart` says otherwise.
    (#"begin="0s; 1s" dur="2s""#, [0...1, 1...3]),
    (#"begin="0s; 1s; 3s" dur="2s" restart="whenNotActive""#, [0...2, 3...5]),
    (#"begin="0s; 3s" dur="2s" restart="never""#, [0...2]),
    // Intervals that begin after the time aren't found.
    (#"begin="2s; 11s" dur="2s""#, [2...4]),
    (#"begin="indefinite" dur="2s""#, []),
    (#"begin="click" dur="2s""#, []),
    (#"begin="1s; click" dur="2s""#, [1...3]),
    (#"dur="2s" end="indefinite""#, [0...2]),
  ]

  @Test("the intervals of an animation", arguments: intervalLists)
  func intervalsOfAnAnimation(attributes: String, expected: [ClosedRange<Double>]) {
    #expect(intervals(#"<set attributeName="x" to="5" "# + attributes + "/>", until: 10) == [expected])
  }

  @Test("syncbase values take the times of the intervals of other animations")
  func syncbases() {
    let found = intervals(
      #"""
      <set id="a" attributeName="x" to="5" begin="1s; 6s" dur="2s"/>
      <set id="b" attributeName="x" to="5" begin="a.end" dur="1s"/>
      <set attributeName="x" to="5" begin="b.begin+0.5s; a.begin-1s" dur="1s"/>
      <set attributeName="x" to="5" begin="missing.end" dur="1s"/>
      """#, until: 10)
    #expect(found == [[1...3, 6...8], [3...4, 8...9], [0...1, 3.5...4.5, 5...6, 8.5...9.5], []])
  }

  @Test("animations that begin at the ends of each other repeat up to the time")
  func cycles() {
    let found = intervals(
      #"""
      <set id="a" attributeName="x" to="5" begin="0s; b.end" dur="1s"/>
      <set id="b" attributeName="x" to="5" begin="a.end" dur="1s"/>
      """#, until: 5)
    #expect(found == [[0...1, 2...3, 4...5], [1...2, 3...4, 5...6]])
  }

  @Test("an end list with only times before a begin stops the intervals")
  func endsBeforeBegins() {
    #expect(intervals(#"<set attributeName="x" to="5" begin="0s; 4s" end="2s"/>"#, until: 10) == [[0...2]])
    // A syncbase end value can resolve later, so the second interval doesn't end.
    let found = intervals(
      #"""
      <set id="a" attributeName="x" to="5" begin="1s" dur="1s"/>
      <set attributeName="x" to="5" begin="0s; 4s" end="a.end"/>
      """#, until: 10)
    #expect(found == [[1...2], [0...2, 4...Double.infinity]])
  }

  @Test("the end of a min-extended interval is its end time for syncbase values")
  func minimumEnds() {
    let found = intervals(
      #"""
      <set id="a" attributeName="x" to="5" dur="1s" repeatCount="5" end="2s" min="8s"/>
      <set attributeName="x" to="5" begin="a.end" dur="1s"/>
      """#, until: 10)
    #expect(found == [[0...8], [8...9]])
    let schedule = SMILSchedule(
      animations: animations(#"<set attributeName="x" to="5" dur="1s" repeatCount="5" end="2s" min="8s"/>"#),
      until: 10)
    #expect(schedule.intervals.first?.first?.playEnd == 5)
  }
}
