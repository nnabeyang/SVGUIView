import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// The document of the content, with its computed values at the time.
private func document(_ content: String, at time: Double) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8)).at(time: time)
}

/// The computed values of the element with the ID `r` at the time.
private func style(_ content: String, at time: Double) throws -> ComputedStyle {
  try #require(document(content, at: time)["r"]).style
}

private func isClose(_ a: Double, _ b: Double) -> Bool {
  abs(a - b) < 1e-9
}

@Suite("Animated styles")
struct AnimatedStyleTests {
  /// Documents with an animated `opacity` on the element `r`, times and the opacity then.
  private static let opacities: [(String, String, Double, Double)] = [
    // A keyframe that's missing at 0% or 100% has the value under the animation.
    ("@keyframes a { 50% { opacity: 0 } }", "animation: a 2s linear", 0.5, 0.4),
    ("@keyframes a { 50% { opacity: 0 } }", "animation: a 2s linear", 1, 0),
    ("@keyframes a { 50% { opacity: 0 } }", "animation: a 2s linear", 1.5, 0.4),
    // Of keyframes with the same offset, the later one wins.
    ("@keyframes a { from { opacity: 0 } from { opacity: 0.5 } to { opacity: 1 } }", "animation: a 1s linear", 0, 0.5),
    // The easing of a keyframe applies to the interval after it, and the animation's to the others.
    (
      "@keyframes a { from { opacity: 0; animation-timing-function: steps(2) } to { opacity: 1 } }",
      "animation: a 1s linear", 0.3, 0
    ),
    (
      "@keyframes a { from { opacity: 0; animation-timing-function: steps(2) } to { opacity: 1 } }",
      "animation: a 1s linear", 0.6, 0.5
    ),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s steps(4)", 0.3, 0.25),
    // The delay and the fill mode.
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear 1s", 0.5, 0.8),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear 1s backwards", 0.5, 0),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear 1s both", 0.5, 0),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear", 3, 0.8),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear forwards", 3, 1),
    // The direction and the count of iterations.
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear 2 alternate", 1.25, 0.75),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear reverse", 0.25, 0.75),
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear 2", 2.5, 0.8),
    // A later animation wins.
    (
      "@keyframes a { from { opacity: 0 } to { opacity: 1 } } @keyframes b { from { opacity: 1 } to { opacity: 0 } }",
      "animation: a 1s linear, b 1s linear", 0.25, 0.75
    ),
    // A paused animation stays at the start.
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s linear paused", 0.5, 0),
    // An easing function that goes outside 0 to 1 doesn't take the opacity outside them.
    (
      "@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s cubic-bezier(0.5, -1, 0.5, 2)",
      0.1, 0
    ),
    (
      "@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: a 1s cubic-bezier(0.5, -1, 0.5, 2)",
      0.9, 1
    ),
    // An animation without keyframes has no effect.
    ("@keyframes a { from { opacity: 0 } to { opacity: 1 } }", "animation: b 1s linear", 0.5, 0.8),
  ]

  @Test("animations override the opacity at the time", arguments: opacities)
  func opacity(keyframes: String, animation: String, time: Double, opacity: Double) throws {
    let content = #"<style>"# + keyframes + #"</style><rect id="r" opacity="0.8" style=""# + animation + #""/>"#
    let style = try style(content, at: time)
    #expect(isClose(style.opacity, opacity), "\(style.opacity)")
  }

  @Test("an important declaration overrides an animation, and the style attribute doesn't")
  func importance() throws {
    let keyframes = "@keyframes a { from { opacity: 0 } to { opacity: 1 } }"
    let important = try style(
      "<style>" + keyframes + " #r { opacity: 0.3 !important }</style>"
        + #"<rect id="r" style="animation: a 1s linear"/>"#, at: 0.5)
    #expect(important.opacity == 0.3)
    let inline = try style(
      "<style>" + keyframes + #"</style><rect id="r" style="opacity: 0.3; animation: a 1s linear"/>"#, at: 0.5)
    #expect(isClose(inline.opacity, 0.5))
  }

  @Test("lengths relative to the font follow an animated font size")
  func animatedFontSize() throws {
    let style = try style(
      "<style>@keyframes f { from { font-size: 10px } to { font-size: 20px } }</style>"
        + #"<rect id="r" style="animation: f 1s linear; stroke-width: 1em"/>"#, at: 0.5)
    #expect(style.strokeWidth == .pixel(15))
  }

  @Test("currentColor is the animated color, also in keyframes")
  func animatedCurrentColor() throws {
    let color = try style(
      "<style>@keyframes c { from { color: rgb(0, 0, 0) } to { color: rgb(255, 0, 0) } }</style>"
        + #"<rect id="r" fill="currentColor" style="animation: c 1s linear"/>"#, at: 0.5)
    let red = try #require(color.resolved(.currentColor as ColorValue).components)
    #expect(isClose(red.red, 0.5) && isClose(red.green, 0) && isClose(red.blue, 0))
    let fill = try style(
      "<style>@keyframes k { from { fill: currentColor } to { fill: rgb(0, 0, 255) } }</style>"
        + #"<rect id="r" color="rgb(255, 0, 0)" style="animation: k 1s linear"/>"#, at: 0.5)
    guard case .color(let mixed) = fill.fill, let components = mixed.components else {
      Issue.record("The fill isn't a color: \(fill.fill)")
      return
    }
    #expect(isClose(components.red, 0.5) && isClose(components.green, 0) && isClose(components.blue, 0.5))
  }

  @Test("values that can't be interpolated change halfway", arguments: [(0.4, FillRule.nonzero), (0.6, .evenodd)])
  func discreteValues(time: Double, rule: FillRule) throws {
    let style = try style(
      "<style>@keyframes d { from { fill-rule: nonzero } to { fill-rule: evenodd } }</style>"
        + #"<rect id="r" style="animation: d 1s linear"/>"#, at: time)
    #expect(style.fillRule == rule)
  }

  @Test("the path data of a path is animated")
  func animatedPathData() throws {
    let base = document(
      #"<style>@keyframes d { to { d: path("M0 0 L20 20") } }</style>"#
        + #"<path id="r" d="M0 0 L10 0" style="animation: d 1s linear"/>"#, at: 0.5)
    let path = try #require(base["r"] as? SVGPathElement)
    #expect(path.data == PathData("M0 0 L15 10"))
  }

  @Test("elements that copy computed values take the animated ones")
  func copiedValues() throws {
    let base = document(
      "<style>@keyframes w { to { width: 20px } }</style>"
        + #"<rect id="r" width="10" height="10" style="animation: w 1s linear"/>"#, at: 0.5)
    let rect = try #require(base["r"] as? SVGRectElement)
    #expect(rect.width == .pixel(15))
  }

  @Test("a document without animations is the same at any time")
  func documentWithoutAnimations() throws {
    let base = SVGParser.parse(
      data: Data(
        #"<svg xmlns="http://www.w3.org/2000/svg"><style>@keyframes a { to { opacity: 0 } }</style><rect/></svg>"#
          .utf8))
    #expect(!base.isAnimated)
    #expect(try #require(base.at(time: 1).root) === base.root)
  }
}
