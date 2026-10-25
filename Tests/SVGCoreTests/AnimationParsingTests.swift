import Foundation
import Testing
import _CSSParser
import _SelectorParser

@testable import SVGCore

/// The values that the declarations of a `style` attribute give the property.
private func declared<P: StyleProperty>(_: P.Type, style text: String) -> P.Specified? {
  CascadedValues(SVGUIInlineStyle(description: text).declarations.map(\.declaration)).declared(P.self)
}

private func easing(_ text: String) -> EasingFunction? {
  declared(AnimationTimingFunctionProperty.self, style: "animation-timing-function: \(text)")?.first
}

private func stylesheet(_ css: String) -> Stylesheet {
  var parser = CSSParser(input: _SelectorParser.CSSParser(input: ParserInput(input: css)))
  return parser.parse()
}

/// Whether two numbers are equal, apart from the precision of the numbers in CSS tokens.
private func isClose(_ a: Double, _ b: Double) -> Bool {
  abs(a - b) < 1e-6
}

@Suite("Parsing animations")
struct AnimationParsingTests {
  @Test(
    "easing functions",
    arguments: [
      ("linear", EasingFunction.linear),
      ("ease", .ease),
      ("EASE-IN", .easeIn),
      ("ease-out", .easeOut),
      ("ease-in-out", .easeInOut),
      ("step-start", .steps(1, .jumpStart)),
      ("step-end", .steps(1, .jumpEnd)),
      ("cubic-bezier(0, 2, 1, -1)", .cubicBezier(x1: 0, y1: 2, x2: 1, y2: -1)),
      ("steps(3)", .steps(3, .jumpEnd)),
      ("steps(3, start)", .steps(3, .jumpStart)),
      ("steps(3, jump-both)", .steps(3, .jumpBoth)),
      ("steps(2, jump-none)", .steps(2, .jumpNone)),
    ])
  func easingFunctions(text: String, expected: EasingFunction) {
    #expect(easing(text) == expected)
  }

  @Test(
    "invalid easing functions",
    arguments: [
      "cubic-bezier(1.5, 0, 1, 1)", "cubic-bezier(0, 0, -0.5, 1)", "cubic-bezier(0, 0, 1)", "steps(0)",
      "steps(1, jump-none)", "steps(1.5)", "steps(2, middle)", "linear(1)", "linear(0 50% 20% 1)", "bounce",
    ])
  func invalidEasingFunctions(text: String) {
    #expect(easing(text) == nil)
  }

  /// The texts of `linear()` and their points, as inputs and outputs.
  private static let linearFunctions: [(String, [(Double, Double)])] = [
    ("linear(0, 1)", [(0.0, 0.0), (1, 1)]),
    ("linear(0, 0.25, 1)", [(0, 0), (0.5, 0.25), (1, 1)]),
    ("linear(0, 0.5 25% 75%, 1)", [(0, 0), (0.25, 0.5), (0.75, 0.5), (1, 1)]),
    ("linear(0, 0.2, 0.4 80%, 1)", [(0, 0), (0.4, 0.2), (0.8, 0.4), (1, 1)]),
    ("linear(0 50%, 0.5 20%, 1)", [(0.5, 0), (0.5, 0.5), (1, 1)]),
    ("linear(50% 0, 1)", [(0.5, 0), (1, 1)]),
  ]

  @Test(
    "linear() fills in the inputs that are missing, and raises the inputs that are less than one before them",
    arguments: linearFunctions)
  func linearInputs(text: String, points: [(Double, Double)]) throws {
    guard case .piecewiseLinear(let parsed) = try #require(easing(text)) else {
      Issue.record("not linear(): \(text)")
      return
    }
    try #require(parsed.count == points.count)
    for (point, (input, output)) in zip(parsed, points) {
      #expect(isClose(point.input, input) && isClose(point.output, output), "\(point) in \(text)")
    }
  }

  @Test("the longhands take comma-separated lists")
  func longhands() {
    #expect(
      declared(AnimationNameProperty.self, style: "animation-name: spin, none, 'a b'")
        == [.keyframes("spin"), .none, .keyframes("a b")])
    #expect(declared(AnimationDurationProperty.self, style: "animation-duration: 1s, 250ms") == [1, 0.25])
    #expect(declared(AnimationDelayProperty.self, style: "animation-delay: -2s") == [-2])
    #expect(
      declared(AnimationIterationCountProperty.self, style: "animation-iteration-count: infinite, 2.5")
        == [.infinite, .count(2.5)])
    #expect(
      declared(AnimationDirectionProperty.self, style: "animation-direction: alternate-reverse, Normal")
        == [.alternateReverse, .normal])
    #expect(declared(AnimationFillModeProperty.self, style: "animation-fill-mode: both") == [.both])
    #expect(declared(AnimationPlayStateProperty.self, style: "animation-play-state: paused") == [.paused])
  }

  @Test(
    "invalid longhands",
    arguments: [
      "animation-name: a, initial", "animation-name: a,", "animation-name: a b", "animation-duration: -1s",
      "animation-duration: 1", "animation-delay: 1px", "animation-iteration-count: -1",
      "animation-direction: forwards",
    ])
  func invalidLonghands(text: String) {
    #expect(SVGUIInlineStyle(description: text).declarations.isEmpty)
  }

  @Test("the longhands aren't presentation attributes")
  func notAttributes() {
    #expect(CascadedValues.presentationAttributes(of: .rect, attributes: ["animation-name": "spin"]).isEmpty)
  }

  @Test("the shorthand sets every longhand, and the ones that it doesn't give to their initial values")
  func shorthand() {
    let style = "animation: 2s ease-in 1s infinite reverse both paused spin, 3s fade"
    #expect(declared(AnimationNameProperty.self, style: style) == [.keyframes("spin"), .keyframes("fade")])
    #expect(declared(AnimationDurationProperty.self, style: style) == [2, 3])
    #expect(declared(AnimationTimingFunctionProperty.self, style: style) == [.easeIn, .ease])
    #expect(declared(AnimationDelayProperty.self, style: style) == [1, 0])
    #expect(declared(AnimationIterationCountProperty.self, style: style) == [.infinite, .count(1)])
    #expect(declared(AnimationDirectionProperty.self, style: style) == [.reverse, .normal])
    #expect(declared(AnimationFillModeProperty.self, style: style) == [.both, .none])
    #expect(declared(AnimationPlayStateProperty.self, style: style) == [.paused, .running])
  }

  @Test(
    "a keyword in the shorthand goes to the first longhand that takes it and isn't set yet",
    arguments: [
      ("animation: none", AnimationName.none, AnimationFillMode.none),
      ("animation: none none", .none, .none),
      ("animation: forwards none", .none, .forwards),
      ("animation: infinite", .none, .none),
      ("animation: 1 infinite", .keyframes("infinite"), .none),
      ("animation: ease ease", .keyframes("ease"), .none),
    ])
  func shorthandKeywords(text: String, name: AnimationName, fillMode: AnimationFillMode) {
    #expect(declared(AnimationNameProperty.self, style: text) == [name])
    #expect(declared(AnimationFillModeProperty.self, style: text) == [fillMode])
  }

  @Test("a negative time in the shorthand is the delay")
  func shorthandNegativeTime() {
    let style = "animation: -1s 2s spin"
    #expect(declared(AnimationDurationProperty.self, style: style) == [2])
    #expect(declared(AnimationDelayProperty.self, style: style) == [-1])
  }

  @Test("a keyword that every property takes sets it on every longhand")
  func shorthandWideKeyword() {
    let cascaded = CascadedValues(SVGUIInlineStyle(description: "animation: inherit").declarations.map(\.declaration))
    for value in [
      cascaded[AnimationNameProperty.self].map { "\($0)" }, cascaded[AnimationDelayProperty.self].map { "\($0)" },
      cascaded[AnimationPlayStateProperty.self].map { "\($0)" },
    ] {
      #expect(value == "inherit")
    }
  }

  @Test(
    "invalid shorthands",
    arguments: ["animation: 1s 2s 3s", "animation: spin spin", "animation: ,", "animation: spin,", "animation: 1px"])
  func invalidShorthands(text: String) {
    #expect(SVGUIInlineStyle(description: text).declarations.isEmpty)
  }

  @Test("important declarations of the shorthand make every longhand important")
  func shorthandImportance() {
    let declarations = SVGUIInlineStyle(description: "animation: spin 1s !important").declarations
    #expect(declarations.count == 8)
    #expect(declarations.allSatisfy { $0.importance == .important })
  }

  @Test("@keyframes rules are kept by their names, and a later rule wins over one with the same name")
  func keyframesRules() throws {
    let sheet = stylesheet(
      """
      @keyframes spin { from { opacity: 0 } to { opacity: 1 } }
      rect { fill: red }
      @-webkit-keyframes "fade" { 50% { fill: blue } }
      @keyframes spin { 0%, 100% { opacity: 0.5 } }
      @media screen { rect { fill: green } }
      @keyframes skip;
      circle { fill: blue }
      """)
    #expect(sheet.rules.count == 2)
    #expect(sheet.rules.map(\.sourceOrder) == [0, 1])
    #expect(Set(sheet.keyframes.keys) == ["spin", "fade"])
    let spin = try #require(sheet.keyframes["spin"])
    try #require(spin.keyframes.count == 1)
    #expect(spin.keyframes[0].offsets == [0, 1])
    #expect(spin.keyframes[0].declarations.declared(OpacityProperty.self) == 0.5)
    #expect(sheet.keyframes["fade"]?.keyframes.first?.offsets == [0.5])
  }

  @Test("keyframes leave out invalid offsets, important declarations and the properties of animations")
  func keyframeContents() throws {
    let sheet = stylesheet(
      """
      @keyframes a {
        from { opacity: 0; fill: red !important; animation-name: b; animation-timing-function: steps(2) }
        150% { opacity: 1 }
        to, 101% { opacity: 1 }
        TO { opacity: 0.25; animation-timing-function: ease, linear }
      }
      """)
    let keyframes = try #require(sheet.keyframes["a"]?.keyframes)
    try #require(keyframes.count == 2)
    #expect(keyframes[0].declarations.declared(OpacityProperty.self) == 0)
    #expect(keyframes[0].declarations[FillProperty.self] == nil)
    #expect(keyframes[0].declarations[AnimationNameProperty.self] == nil)
    #expect(keyframes[0].easing == .steps(2, .jumpEnd))
    #expect(keyframes[1].offsets == [1])
    #expect(keyframes[1].easing == nil)
  }

  @Test("@keyframes names that are keywords are invalid")
  func keyframesNames() {
    #expect(stylesheet("@keyframes none { to { opacity: 0 } }").keyframes.isEmpty)
    #expect(stylesheet("@keyframes INITIAL { to { opacity: 0 } }").keyframes.isEmpty)
    #expect(stylesheet("@keyframes 'none' { to { opacity: 0 } }").keyframes.keys.first == "none")
  }
}
