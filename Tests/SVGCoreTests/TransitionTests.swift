import Foundation
import Testing

@testable import SVGCore

/// The resolver of an element whose `color` is lime.
private let resolver: StyleResolver = {
  var style = ComputedStyle.initial
  style.color = SVGAttributeScanner.parseColor(description: "lime")!
  return StyleResolver(style: style, parent: .initial, root: .initial)
}()

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The computed values of the element with an ID in a document at a time.
private func style(of id: String, in base: SVGBaseContext, at time: Double) -> ComputedStyle? {
  base.at(time: time).root?.elements.first { $0.base.id == id }?.style
}

/// The document with an attribute of the element with an ID changed at a time.
private func changing(
  _ base: SVGBaseContext, _ id: String = "a", _ name: String = "class", to value: String?, at time: Double,
  startsTransitions: Bool = true
) throws -> SVGBaseContext {
  let element = try #require(base.document.element(id: id))
  return base.changingAttributes([element: [name: value]], at: time, startsTransitions: startsTransitions)
}

/// Whether two numbers are equal, apart from rounding.
private func isClose(_ a: Double?, _ b: Double) -> Bool {
  a.map { abs($0 - b) < 1e-9 } ?? false
}

/// The computed value of a declaration of a property.
private func computed<P: StyleProperty>(_: P.Type, _ text: String) -> P.Computed {
  resolver.computed(P.declared(attribute: text), of: P.self)
}

@Suite("CSS Transitions")
struct TransitionTests {
  @Test(
    "computed values are equal when they're the same value however they're written",
    arguments: [
      ("red", "#f00", true), ("red", "rgb(255, 0, 0)", true), ("red", "rgba(255, 0, 0, 0.5)", false),
      ("url(#a)", "url(#a)", true), ("url(#a)", "url(#b)", false), ("none", "black", false),
      ("currentColor", "currentColor", true),
    ])
  func equalPaints(lhs: String, rhs: String, expected: Bool) {
    #expect((computed(FillProperty.self, lhs) == computed(FillProperty.self, rhs)) == expected)
  }

  @Test(
    "a transition interpolates values whose values between them exist, with currentColor as the color of the element",
    arguments: [
      ("red", "blue", true), ("currentColor", "blue", true), ("none", "blue", false), ("url(#a)", "blue", false),
    ])
  func interpolatesPaints(from: String, to: String, expected: Bool) {
    let from = computed(FillProperty.self, from)
    let to = computed(FillProperty.self, to)
    #expect(FillProperty.interpolates(from, to, in: resolver) == expected)
  }

  @Test("values of properties that don't interpolate, or that can't, change discretely")
  func discreteValues() {
    #expect(OpacityProperty.interpolates(0, 1, in: resolver))
    #expect(StopColorProperty.interpolates(.currentColor, .color(.named(SVGColorName(name: "red"))), in: resolver))
    #expect(!DisplayProperty.interpolates(.inline, .none, in: resolver))
    #expect(!WidthProperty.interpolates(nil, .number(1), in: resolver))
    #expect(WidthProperty.interpolates(.number(2), .number(1), in: resolver))
  }

  /// An element whose opacity goes to 0 in a second with `.on`.
  private static let fade =
    "<style>rect { transition: opacity 1s linear } .on { opacity: 0 } .low { opacity: 0.2 }</style>"
    + #"<rect id="a" width="10" height="10"/>"#

  @Test("a change starts a transition at its time, which ends at the new value")
  func startsTransition() throws {
    let base = try changing(parse(Self.fade), to: "on", at: 2)
    #expect(base.isAnimated)
    #expect(style(of: "a", in: base, at: 2)?.opacity == 1)
    #expect(isClose(style(of: "a", in: base, at: 2.5)?.opacity, 0.5))
    #expect(style(of: "a", in: base, at: 3)?.opacity == 0)
    #expect(base.animationEnd() == 3)
    // Before the change, the document shows the new value.
    #expect(style(of: "a", in: base, at: 1)?.opacity == 0)
  }

  @Test("the start value stays during the delay, and a negative delay starts partway")
  func delay() throws {
    let delayed = try changing(parse(Self.fade.replacingOccurrences(of: "linear", with: "linear 1s")), to: "on", at: 2)
    #expect(style(of: "a", in: delayed, at: 2.5)?.opacity == 1)
    #expect(isClose(style(of: "a", in: delayed, at: 3.5)?.opacity, 0.5))
    #expect(delayed.animationEnd() == 4)
    let early = try changing(parse(Self.fade.replacingOccurrences(of: "linear", with: "linear -0.5s")), to: "on", at: 2)
    #expect(isClose(style(of: "a", in: early, at: 2)?.opacity, 0.5))
    #expect(early.animationEnd() == 2.5)
  }

  @Test(
    "a change starts no transition of a property that transition-property doesn't name, without a duration, or of values that are the same or don't interpolate",
    arguments: [
      ("rect { transition: fill 1s } .on { opacity: 0 }", "on"),
      ("rect { transition: opacity 0s } .on { opacity: 0 }", "on"),
      ("rect { transition: opacity 1s -1s } .on { opacity: 0 }", "on"),
      ("rect { transition: none } .on { opacity: 0 }", "on"),
      ("rect { fill: red; transition: fill 1s } .on { fill: #f00 }", "on"),
      ("rect { fill: none; transition: fill 1s } .on { fill: red }", "on"),
      ("rect { transition: all 1s } .on { display: none }", "on"),
    ])
  func noTransition(css: String, className: String) throws {
    let base = parse("<style>\(css)</style>" + #"<rect id="a" width="10" height="10"/>"#)
    let changed = try changing(base, to: className, at: 1)
    #expect(changed.animations.transitions.isEmpty)
    #expect(changed.animationEnd() == 0)
  }

  @Test("allow-discrete transitions values that don't interpolate, which change halfway")
  func allowDiscrete() throws {
    let base = parse(
      "<style>rect { fill: none; transition: fill 1s linear allow-discrete } .on { fill: red }</style>"
        + #"<rect id="a" width="10" height="10"/>"#)
    let changed = try changing(base, to: "on", at: 0)
    #expect(style(of: "a", in: changed, at: 0.4)?.fill == Paint.none)
    #expect(style(of: "a", in: changed, at: 0.6)?.fill == FillProperty.parse("red", origin: .css))
  }

  @Test("changing a value back reverses the transition from where it is, in the time that it has taken")
  func reverses() throws {
    let started = try changing(parse(Self.fade), to: "on", at: 0)
    let reversed = try changing(started, to: nil, at: 0.25)
    #expect(isClose(style(of: "a", in: reversed, at: 0.25)?.opacity, 0.75))
    #expect(isClose(style(of: "a", in: reversed, at: 0.375)?.opacity, 0.875))
    #expect(reversed.animationEnd() == 0.5)
    // Reversing the reversed transition halfway shortens it by half of the part that the first one took.
    let again = try changing(reversed, to: "on", at: 0.375)
    #expect(isClose(style(of: "a", in: again, at: 0.375)?.opacity, 0.875))
    #expect(again.animationEnd() == 0.375 + 0.875)
  }

  @Test("a change to another value starts a transition from the value that the running one is at")
  func changesTarget() throws {
    let started = try changing(parse(Self.fade), to: "on", at: 0)
    let changed = try changing(started, to: "low", at: 0.5)
    #expect(isClose(style(of: "a", in: changed, at: 0.5)?.opacity, 0.5))
    #expect(isClose(style(of: "a", in: changed, at: 1)?.opacity, 0.35))
    #expect(changed.animationEnd() == 1.5)
    // A change that keeps the value keeps the transition.
    let kept = try changing(changed, "a", "data-x", to: "1", at: 1)
    #expect(kept.animationEnd() == 1.5)
    // A change that stops naming the property cancels it.
    let cancelled = try changing(kept, "a", "style", to: "transition: none", at: 1)
    #expect(cancelled.animations.transitions.isEmpty)
    #expect(style(of: "a", in: cancelled, at: 1)?.opacity == 0.2)
  }

  @Test("a change of a value that an animation changes starts no transition")
  func animatedValue() throws {
    let base = parse(
      "<style>@keyframes k { from, to { opacity: 0.5 } } rect { animation: k 10s forwards; transition: opacity 1s } "
        + ".on { opacity: 0 }</style>" + #"<rect id="a" width="10" height="10"/>"#)
    #expect(try changing(base, to: "on", at: 1).animations.transitions.isEmpty)
  }

  @Test("a change of an inherited value starts the transitions of the descendants that inherit it")
  func inherited() throws {
    let base = parse(
      #"<g id="g" fill="rgb(255, 0, 0)"><rect id="a" width="10" height="10" style="transition: fill 1s linear"/></g>"#
    )
    let changed = try changing(base, "g", "fill", to: "rgb(0, 0, 255)", at: 0)
    let element = try #require(base.document.element(id: "a"))
    #expect(changed.animations.transitions.keys.map { $0 } == [element])
    guard case .color(let color) = style(of: "a", in: changed, at: 0.5)?.fill, let components = color.components else {
      Issue.record("not a color")
      return
    }
    #expect(isClose(components.red, 0.5) && isClose(components.blue, 0.5))
  }

  @Test("transitions override important declarations")
  func important() throws {
    let base = parse(
      "<style>rect { opacity: 1 !important; transition: opacity 1s linear } rect.on { opacity: 0 !important }</style>"
        + #"<rect id="a" width="10" height="10"/>"#)
    let changed = try changing(base, to: "on", at: 0)
    #expect(isClose(style(of: "a", in: changed, at: 0.5)?.opacity, 0.5))
  }

  @Test("a change that doesn't start transitions changes the values at once, and cancels the running ones")
  func withoutTransitions() throws {
    let base = parse(Self.fade)
    #expect(try changing(base, to: "on", at: 0, startsTransitions: false).animations.transitions.isEmpty)
    let started = try changing(base, to: "on", at: 0)
    let cancelled = try changing(started, "a", "data-x", to: "1", at: 0.5, startsTransitions: false)
    #expect(cancelled.animations.transitions.isEmpty)
    #expect(style(of: "a", in: cancelled, at: 0.5)?.opacity == 0)
    // A transition that has ended is left out.
    #expect(try changing(started, "a", "data-x", to: "1", at: 1).animations.transitions.isEmpty)
  }

  @Test("the elements with transitions of transform or opacity composite in layers, and others paint again")
  func layers() throws {
    let base = parse(
      "<style>rect { transition: opacity 1s, fill 1s } .on { opacity: 0 } .red { fill: red }</style>"
        + #"<rect id="a" width="10" height="10"/><rect id="b" width="10" height="10"/>"#)
    let a = try #require(base.document.element(id: "a"))
    let b = try #require(base.document.element(id: "b"))
    let changed = base.changingAttributes([a: ["class": "on"], b: ["class": "red"]], at: 0)
    #expect(changed.elementsWithAnimatedCompositing() == [a])
    #expect(changed.elementsWithAnimatedPainting().contains(b))
    #expect(!changed.elementsWithAnimatedPainting().contains(a))
  }

  @Test(
    "display is the value that isn't none between none and another value, and changes halfway between other values",
    arguments: [
      (CSSDisplay.inline, CSSDisplay.none, 0.0, CSSDisplay.inline), (.inline, .none, 0.5, .inline),
      (.inline, .none, 0.99, .inline), (.inline, .none, 1, .none), (.none, .inline, 0, .none),
      (.none, .inline, 0.01, .inline), (.none, .inline, 1, .inline), (.inline, .block, 0.49, .inline),
      (.inline, .block, 0.5, .block),
    ])
  func displayInterpolation(from: CSSDisplay, to: CSSDisplay, progress: Double, expected: CSSDisplay) {
    #expect(DisplayProperty.interpolated(from, to, progress: progress, in: resolver) == expected)
  }

  @Test("an animation of display to none shows the element until its end")
  func displayAnimation() {
    let base = parse(
      "<style>@keyframes k { to { display: none } } rect { animation: k 1s linear forwards }</style>"
        + #"<rect id="a" width="10" height="10"/>"#)
    #expect(style(of: "a", in: base, at: 0.99)?.display == .inline)
    #expect(style(of: "a", in: base, at: 1)?.display == CSSDisplay.none)
  }
}
