import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The opacity of the element with an ID in a document at a time.
private func opacity(of id: String, in base: SVGBaseContext, at time: Double) -> Double? {
  base.at(time: time).root?.elements.first { $0.base.id == id }?.style.opacity
}

@Suite("Playing CSS animations on the timeline")
struct AnimationPlaybackTests {
  /// An element whose opacity goes from 0 to 1 in 2 seconds after a delay of 1 second, and stays at 1.
  private static let fade =
    "<style>@keyframes f { from { opacity: 0 } to { opacity: 1 } }</style>"
    + #"<rect id="a" width="10" height="10" style="animation: f 2s linear 1s forwards"/>"#

  @Test("the local time advances with the timeline at the rate, and pausing, playing, seeking and changing the rate keep it")
  func localTime() {
    var playback = AnimationPlayback(startTime: 2)
    #expect(playback.localTime(at: 2) == 0)
    #expect(playback.localTime(at: 5) == 3)
    playback.pause(at: 5)
    #expect(playback.isPaused)
    #expect(playback.localTime(at: 10) == 3)
    playback.play(at: 10)
    #expect(playback.localTime(at: 11) == 4)
    playback.setRate(2, at: 11)
    #expect(playback.localTime(at: 12) == 6)
    playback.seek(to: 1, at: 12)
    #expect(playback.localTime(at: 13) == 3)
    playback.setRate(-1, at: 13)
    #expect(playback.localTime(at: 14) == 2)
    // A paused animation holds the time that it's moved to, and keeps it when its rate changes.
    playback.pause(at: 14)
    playback.seek(to: 5, at: 20)
    playback.setRate(0, at: 20)
    #expect(playback.localTime(at: 30) == 5)
    playback.play(at: 30)
    #expect(playback.localTime(at: 40) == 5)
    #expect(AnimationPlayback(isPaused: true).localTime(at: 7) == 0)
  }

  @Test(
    "a playing animation finishes at its end, or at its start when it plays backward",
    arguments: [
      (1.0, 5.0, true), (1, 4.9, false), (-1, 0, true), (-1, 0.1, false), (0, 100, false),
    ])
  func finished(rate: Double, localTime: Double, expected: Bool) {
    var playback = AnimationPlayback()
    playback.seek(to: localTime, at: 0)
    playback.setRate(rate, at: 0)
    #expect(playback.isFinished(at: 0, end: 5) == expected)
    playback.pause(at: 0)
    #expect(!playback.isFinished(at: 0, end: 5))
  }

  @Test("the animations of a document in document order, with the numbers of names that repeat")
  func cssAnimations() {
    let base = parse(
      "<style>@keyframes f { to { opacity: 1 } } @keyframes g { to { opacity: 1 } }</style>"
        + #"<rect id="a" style="animation-name: f, none, g, f, unknown"/><g id="b" style="animation: g 1s"/>"#)
    let ids = base.cssAnimations()
    #expect(ids.map(\.name) == ["f", "g", "f", "g"])
    #expect(ids.map(\.occurrence) == [0, 0, 1, 0])
    #expect(Set(ids.prefix(3).map(\.element)).count == 1)
    #expect(ids[3].element != ids[0].element)
  }

  @Test("an animation without a playback of its own plays from the time that the document was loaded")
  func defaultPlayback() throws {
    let base = parse(Self.fade)
    let id = try #require(base.cssAnimations().first)
    #expect(base.playback(of: id) == AnimationPlayback())
    #expect(opacity(of: "a", in: base, at: 2) == 0.5)
    #expect(base.animationEnd() == 3)
    #expect(!base.isFinished(id, at: 2.9))
    #expect(base.isFinished(id, at: 3))
    let paused = parse(Self.fade.replacingOccurrences(of: "forwards", with: "forwards paused"))
    #expect(paused.playback(of: try #require(paused.cssAnimations().first)) == AnimationPlayback(isPaused: true))
    #expect(paused.animationEnd() == 0)
    #expect(base.playback(of: CSSAnimationID(element: id.element, name: "f", occurrence: 1)) == nil)
    #expect(base.isFinished(CSSAnimationID(element: id.element, name: "g", occurrence: 0), at: 0))
  }

  @Test(
    "an animation plays as its playback gives, and the document stops changing when it finishes",
    arguments: [
      // A start time, a local time to pause at or `nil`, a rate, the time to look at, the opacity then, and the
      // end of the animations.
      (4.0, nil as Double?, 1.0, 6.0, 0.5, 7.0),
      (0, 2, 1, 10, 0.5, 0),
      (0, nil, 2, 1, 0.5, 1.5),
      // Playing backward from the end, which it stays at before the time that it starts playing.
      (0, nil, -1, 1, 0.5, 3),
    ] as [(Double, Double?, Double, Double, Double, Double)])
  func playback(
    startTime: Double, pausedAt: Double?, rate: Double, time: Double, expected: Double, end: Double
  ) throws {
    let base = parse(Self.fade)
    let id = try #require(base.cssAnimations().first)
    var playback = AnimationPlayback(startTime: startTime)
    if rate < 0 {
      playback.seek(to: 3, at: 0)
    }
    playback.setRate(rate, at: startTime)
    if let pausedAt {
      playback.seek(to: pausedAt, at: 0)
      playback.pause(at: 0)
    }
    let played = base.settingPlayback(playback, of: id)
    #expect(opacity(of: "a", in: played, at: time) == expected)
    #expect(played.animationEnd() == end)
  }

  @Test("a change starts the animations that it makes an element run at the time of the change")
  func changeStartsAnimations() throws {
    let base = parse(Self.fade.replacingOccurrences(of: #"style="animation"#, with: #"class="x" data-style="animation"#))
    let a = try #require(base.document.element(id: "a"))
    #expect(base.cssAnimations().isEmpty)
    // The animation starts at 5 seconds, after its delay of 1 second.
    let started = base.changingAttributes([a: ["style": "animation: f 2s linear 1s forwards"]], at: 5)
    let id = try #require(started.cssAnimations().first)
    #expect(started.playback(of: id) == AnimationPlayback(startTime: 5))
    #expect(opacity(of: "a", in: started, at: 7) == 0.5)
    #expect(started.animationEnd() == 8)
    // A change that keeps the animation keeps how it plays, even with another duration.
    let kept = started.changingAttributes([a: ["style": "animation: f 4s linear 1s forwards", "fill": "red"]], at: 6)
    #expect(kept.playback(of: id) == AnimationPlayback(startTime: 5))
    #expect(opacity(of: "a", in: kept, at: 8) == 0.5)
    // An animation that a change removes is no longer kept, and starts again when it's run again.
    let removed = kept.changingAttributes([a: ["style": nil]], at: 7)
    #expect(removed.cssAnimations().isEmpty)
    #expect(removed.animations.playback.isEmpty)
    let again = removed.changingAttributes([a: ["style": "animation: f 2s linear 1s forwards"]], at: 9)
    #expect(again.playback(of: id) == AnimationPlayback(startTime: 9))
  }

  @Test("the animations that a document runs as it's loaded play from the time that it was loaded")
  func changeKeepsAnimations() throws {
    let base = parse(Self.fade + #"<rect id="b"/>"#)
    let b = try #require(base.document.element(id: "b"))
    let changed = base.changingAttributes([b: ["fill": "red"]], at: 5)
    #expect(changed.animations.playback.isEmpty)
    #expect(opacity(of: "a", in: changed, at: 2) == 0.5)
  }

  @Test("a change of animation-play-state pauses an animation where it is, and plays it on from there")
  func changePlayState() throws {
    let base = parse(Self.fade)
    let a = try #require(base.document.element(id: "a"))
    let id = try #require(base.cssAnimations().first)
    let paused = base.changingAttributes(
      [a: ["style": "animation: f 2s linear 1s forwards; animation-play-state: paused"]], at: 2)
    #expect(paused.playback(of: id)?.isPaused == true)
    #expect(opacity(of: "a", in: paused, at: 10) == 0.5)
    #expect(paused.animationEnd() == 0)
    let played = paused.changingAttributes([a: ["style": "animation: f 2s linear 1s forwards"]], at: 10)
    #expect(opacity(of: "a", in: played, at: 10) == 0.5)
    #expect(opacity(of: "a", in: played, at: 10.5) == 0.75)
    #expect(played.animationEnd() == 11)
  }
}
