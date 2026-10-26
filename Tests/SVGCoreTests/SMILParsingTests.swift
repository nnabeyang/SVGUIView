import Foundation
import Testing

@testable import SVGCore

/// The SMIL animations of a document with the given content.
private func animations(_ content: String) -> [SMILAnimation] {
  let svg =
    #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 20 20">"#
    + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8)).animations.smil
}

/// The animation of an `<animate>` element of a rectangle with the given attributes.
private func animation(_ attributes: String) -> SMILAnimation? {
  animations(#"<rect width="10" height="10"><animate attributeName="x" "# + attributes + "/></rect>").first
}

@Suite("Parsing SMIL animations")
struct SMILParsingTests {
  @Test(
    "clock values",
    arguments: [
      ("02:30:03", 9003.0),
      ("50:00:10.25", 180_010.25),
      ("02:33", 153),
      ("00:10.5", 10.5),
      ("3.2h", 11_520),
      ("45min", 2700),
      ("30s", 30),
      ("5ms", 0.005),
      ("12.467", 12.467),
      (" 2s ", 2),
    ])
  func clockValues(text: String, seconds: Double) throws {
    let value = try #require(SMILClock.seconds(text[...]))
    #expect(abs(value - seconds) < 1e-9)
  }

  @Test(
    "invalid clock values",
    arguments: ["", "s", "-1s", "1.s", ".5s", "1e2s", "2:30", "00:60", "00:00:60", "1sec", "1 s", "a:00"])
  func invalidClockValues(text: String) {
    #expect(SMILClock.seconds(text[...]) == nil)
  }

  /// The values of `begin` and `end` lists.
  private static let lists: [(String, [SMILTimeValue])] = [
    ("1s", [.offset(1)]),
    ("-0.5s", [.offset(-0.5)]),
    ("+ 2s", [.offset(2)]),
    ("0; 3s ;", [.offset(0), .offset(3)]),
    ("a.end", [.syncbase(id: "a", event: .end, offset: 0)]),
    ("a.begin+1.5s", [.syncbase(id: "a", event: .begin, offset: 1.5)]),
    ("anim-1.end - 2s", [.syncbase(id: "anim-1", event: .end, offset: -2)]),
    ("a.b.begin", [.syncbase(id: "a.b", event: .begin, offset: 0)]),
    ("indefinite", [.indefinite]),
    ("click", [.unresolved]),
    ("a.click+1s", [.unresolved]),
    ("a.repeat(2)", [.unresolved]),
    ("accessKey(s)", [.unresolved]),
    ("wallclock(2026-10-26T12:00:00Z)", [.unresolved]),
    ("2s; a.end; click", [.offset(2), .syncbase(id: "a", event: .end, offset: 0), .unresolved]),
  ]

  @Test("begin and end lists", arguments: lists)
  func timeLists(text: String, expected: [SMILTimeValue]) {
    #expect(SMILTimeValue.list(text) == expected)
  }

  @Test("an invalid value makes the whole list invalid", arguments: ["1s; 2x", "a.end+", ".end", "", " ; "])
  func invalidTimeLists(text: String) {
    #expect(SMILTimeValue.list(text) == nil)
  }

  @Test("an animation changes its parent, or the element that its href references")
  func targets() throws {
    let found = animations(
      ##"""
      <rect id="r" width="10" height="10"><animate attributeName="x" to="5"/></rect>
      <circle id="c" r="5"/>
      <animate href="#c" attributeName="r" to="2"/>
      <set xlink:href="#c" attributeName="fill" to="red"/>
      <animate href="#missing" attributeName="x" to="5"/>
      <g><animateTransform attributeName="transform" type="scale" to="2"/></g>
      """##)
    try #require(found.count == 4)
    #expect(found.map(\.kind) == [.animate, .animate, .set, .animateTransform])
    #expect(found.map(\.targetName) == [.rect, .circle, .circle, .g])
    #expect(found[1].target == found[2].target)
    #expect(found[0].target != found[1].target)
    #expect(found.map(\.attributeName) == ["x", "r", "fill", "transform"])
  }

  @Test(
    "values come from values, from to or from by, in this order",
    arguments: [
      (#"values="1; 2;3;" from="5" to="6""#, SMILAnimation.Values.list(["1", "2", "3"])),
      (#"from="1" to="2""#, .to(from: "1", to: "2")),
      (#"to="2""#, .to(from: nil, to: "2")),
      (#"from="1" by="2""#, .by(from: "1", by: "2")),
      (#"by="2" to="3""#, .to(from: nil, to: "3")),
    ])
  func values(attributes: String, expected: SMILAnimation.Values) throws {
    #expect(try #require(animation(attributes)).values == expected)
  }

  @Test(
    "an animation without values, or with an invalid list of times or splines, is ignored",
    arguments: [
      #"from="1""#,
      #"values="1;2;3" keyTimes="0;1""#,
      #"values="1;2" keyTimes="0.5;1""#,
      #"values="1;2" keyTimes="0;0.9""#,
      #"values="1;2;3" keyTimes="0;0.6;0.4""#,
      #"values="1;2" keyTimes="0;x""#,
      #"values="1;2;3" calcMode="spline" keySplines="0 0 1 1""#,
      #"values="1;2" calcMode="spline" keySplines="0 0 1 2""#,
      #"values="1;2" calcMode="spline""#,
    ])
  func invalidAnimations(attributes: String) {
    #expect(animation(attributes) == nil)
  }

  @Test("an attribute name is needed, except for animateMotion")
  func attributeNames() {
    let found = animations(
      #"""
      <rect width="10" height="10">
        <animate to="5"/>
        <animateMotion path="M0 0 L10 10" dur="1s"/>
      </rect>
      """#)
    #expect(found.map(\.kind) == [.animateMotion])
    #expect(found.first?.attributeName == nil)
    #expect(found.first?.values == SMILAnimation.Values.none)
    #expect(found.first?.calcMode == .paced)
  }

  @Test("the times and the splines of the values")
  func keyTimesAndSplines() throws {
    let discrete = try #require(animation(#"values="1;2;3" calcMode="discrete" keyTimes="0;0.2;0.5""#))
    #expect(discrete.keyTimes == [0, 0.2, 0.5])
    let spline = try #require(
      animation(#"values="1;2;3" calcMode="spline" keyTimes="0;0.5;1" keySplines="0 0 1 1; .5,0 .5,1""#))
    #expect(spline.keySplines == [.cubicBezier(x1: 0, y1: 0, x2: 1, y2: 1), .cubicBezier(x1: 0.5, y1: 0, x2: 0.5, y2: 1)])
    // A paced animation ignores its times.
    let paced = try #require(animation(#"values="1;2;3" calcMode="paced" keyTimes="0;1""#))
    #expect(paced.keyTimes == nil)
  }

  @Test("the timing attributes")
  func timing() throws {
    let animation = try #require(
      animation(
        #"to="5" begin="1s; a.end" end="5s" dur="2s" repeatCount="2.5" repeatDur="4s" min="1s" max="3s" restart="whenNotActive" fill="freeze" additive="sum" accumulate="sum""#
      ))
    #expect(animation.begin == [.offset(1), .syncbase(id: "a", event: .end, offset: 0)])
    #expect(animation.end == [.offset(5)])
    #expect(animation.duration == 2)
    #expect(animation.repeatCount == .count(2.5))
    #expect(animation.repeatDuration == 4)
    #expect(animation.minimum == 1)
    #expect(animation.maximum == 3)
    #expect(animation.restart == .whenNotActive)
    #expect(animation.fill == .freeze)
    #expect(animation.isAdditive)
    #expect(animation.isAccumulative)
  }

  @Test("the defaults of the timing attributes, and invalid values")
  func timingDefaults() throws {
    let defaults = try #require(animation(#"to="5""#))
    #expect(defaults.begin == [.offset(0)])
    #expect(defaults.end == nil)
    #expect(defaults.duration == nil)
    #expect(defaults.repeatCount == nil)
    #expect(defaults.repeatDuration == nil)
    #expect(defaults.minimum == 0)
    #expect(defaults.maximum == .infinity)
    #expect(defaults.restart == .always)
    #expect(defaults.fill == .remove)
    #expect(!defaults.isAdditive)
    let invalid = try #require(
      animation(#"to="5" begin="1x" dur="0s" repeatCount="-1" repeatDur="indefinite" min="3s" max="1s""#))
    #expect(invalid.begin == [.offset(0)])
    #expect(invalid.duration == nil)
    #expect(invalid.repeatCount == nil)
    #expect(invalid.repeatDuration == .infinity)
    #expect(invalid.minimum == 0)
    #expect(invalid.maximum == .infinity)
  }

  @Test("a set element only has a to value, and doesn't add")
  func set() throws {
    let found = animations(
      #"<rect width="10" height="10"><set attributeName="fill" values="red;blue" to="lime" additive="sum"/></rect>"#)
    let set = try #require(found.first)
    #expect(set.values == .to(from: nil, to: "lime"))
    #expect(set.calcMode == .discrete)
    #expect(!set.isAdditive)
  }

  @Test("animation elements aren't rendered, and the text around them stays with their parent")
  func animationElements() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <text>Hello<animate attributeName="x" to="5"/>!</text>
        <rect width="10" height="10"><set attributeName="fill" to="red"/></rect>
        <path id="p" d="M0 0 L10 10"/>
        <circle r="2"><animateMotion dur="1s"><mpath href="#p"/></animateMotion></circle>
      </svg>
      """#
    let context = SVGParser.parse(data: Data(svg.utf8))
    let root = try #require(context.document.root)
    #expect(root.children.flatMap { $0.children.map(\.name) } == [.animate, .set, .animateMotion])
    #expect(root.children[0].text == "Hello!")
    #expect(context.root?.children.map(\.type) == [.text, .rect, .path, .circle])
    #expect(context.root?.children.allSatisfy { $0.children.isEmpty } == true)
    #expect(context.animations.smil.last?.motionPath == "p")
  }
}
