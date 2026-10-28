import Foundation
import Testing
import _CSSParser
import _SelectorParser

@testable import SVGCore

/// The values that the declarations of a `style` attribute give the property.
private func declared<P: StyleProperty>(_: P.Type, style text: String) -> P.Specified? {
  CascadedValues(SVGUIInlineStyle(description: text).declarations.map(\.declaration)).declared(P.self)
}

private func stylesheet(_ css: String) -> Stylesheet {
  var parser = CSSParser(input: _SelectorParser.CSSParser(input: ParserInput(input: css)))
  return parser.parse()
}

/// The computed values of the element with an ID in a document.
private func style(of id: String, in content: String) -> ComputedStyle? {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8)).at(time: 0).root?.elements.first { $0.base.id == id }?.style
}

@Suite("Parsing transitions")
struct TransitionParsingTests {
  @Test("the longhands take comma-separated lists")
  func longhands() {
    #expect(
      declared(TransitionPropertyProperty.self, style: "transition-property: OPACITY, foo, all, stroke-width")
        == [.property(.opacity), .unrecognized("foo"), .all, .property(.strokeWidth)])
    #expect(declared(TransitionPropertyProperty.self, style: "transition-property: none") == [.none])
    #expect(declared(TransitionDurationProperty.self, style: "transition-duration: 1s, 250ms") == [1, 0.25])
    #expect(
      declared(TransitionTimingFunctionProperty.self, style: "transition-timing-function: linear, steps(2)")
        == [.linear, .steps(2, .jumpEnd)])
    #expect(declared(TransitionDelayProperty.self, style: "transition-delay: -2s, 0s") == [-2, 0])
    #expect(
      declared(TransitionBehaviorProperty.self, style: "transition-behavior: Allow-Discrete, normal")
        == [.allowDiscrete, .normal])
  }

  @Test(
    "invalid longhands",
    arguments: [
      "transition-property: a, none", "transition-property: none, a", "transition-property: initial, a",
      "transition-property: a,", "transition-property: a b", "transition-property: 1s",
      "transition-duration: -1s", "transition-duration: 1", "transition-delay: 1px",
      "transition-timing-function: bounce", "transition-behavior: discrete",
    ])
  func invalidLonghands(text: String) {
    #expect(SVGUIInlineStyle(description: text).declarations.isEmpty)
  }

  @Test("the longhands aren't presentation attributes")
  func notAttributes() {
    #expect(CascadedValues.presentationAttributes(of: .rect, attributes: ["transition-duration": "1s"]).isEmpty)
  }

  @Test("the shorthand sets every longhand, and the ones that it doesn't give to their initial values")
  func shorthand() {
    let style = "transition: opacity 1s ease-in 2s allow-discrete, 3s FILL"
    #expect(declared(TransitionPropertyProperty.self, style: style) == [.property(.opacity), .property(.fill)])
    #expect(declared(TransitionDurationProperty.self, style: style) == [1, 3])
    #expect(declared(TransitionTimingFunctionProperty.self, style: style) == [.easeIn, .ease])
    #expect(declared(TransitionDelayProperty.self, style: style) == [2, 0])
    #expect(declared(TransitionBehaviorProperty.self, style: style) == [.allowDiscrete, .normal])
    #expect(declared(TransitionPropertyProperty.self, style: "transition: 1s") == [.all])
  }

  @Test(
    "an identifier in the shorthand is the easing function or the behavior first, and the property after them",
    arguments: [
      ("transition: ease", TransitionProperty.all, EasingFunction.ease, TransitionBehavior.normal),
      ("transition: ease ease", .unrecognized("ease"), .ease, .normal),
      ("transition: linear ease", .unrecognized("ease"), .linear, .normal),
      ("transition: normal", .all, .ease, .normal),
      ("transition: allow-discrete normal", .unrecognized("normal"), .ease, .allowDiscrete),
      ("transition: none", .none, .ease, .normal),
      ("transition: all steps(2)", .all, .steps(2, .jumpEnd), .normal),
    ])
  func shorthandIdentifiers(
    text: String, property: TransitionProperty, easing: EasingFunction, behavior: TransitionBehavior
  ) {
    #expect(declared(TransitionPropertyProperty.self, style: text) == [property])
    #expect(declared(TransitionTimingFunctionProperty.self, style: text) == [easing])
    #expect(declared(TransitionBehaviorProperty.self, style: text) == [behavior])
  }

  @Test("a negative time in the shorthand is the delay")
  func shorthandNegativeTime() {
    let style = "transition: -1s 2s"
    #expect(declared(TransitionDurationProperty.self, style: style) == [2])
    #expect(declared(TransitionDelayProperty.self, style: style) == [-1])
  }

  @Test("a keyword that every property takes sets it on every longhand")
  func shorthandWideKeyword() {
    let cascaded = CascadedValues(SVGUIInlineStyle(description: "transition: inherit").declarations.map(\.declaration))
    for value in [
      cascaded[TransitionPropertyProperty.self].map { "\($0)" }, cascaded[TransitionDelayProperty.self].map { "\($0)" },
      cascaded[TransitionBehaviorProperty.self].map { "\($0)" },
    ] {
      #expect(value == "inherit")
    }
  }

  @Test(
    "invalid shorthands",
    arguments: [
      "transition: none, opacity 1s", "transition: opacity, none", "transition: 1s 2s 3s", "transition: a b",
      "transition: ,", "transition: a,", "transition: 1px", "transition: initial 1s", "transition: ease ease ease",
    ])
  func invalidShorthands(text: String) {
    #expect(SVGUIInlineStyle(description: text).declarations.isEmpty)
  }

  @Test("important declarations of the shorthand make every longhand important")
  func shorthandImportance() {
    let declarations = SVGUIInlineStyle(description: "transition: opacity 1s !important").declarations
    #expect(declarations.count == 5)
    #expect(declarations.allSatisfy { $0.importance == .important })
  }

  @Test("the computed values are the lists that the cascade gives, and the initial values aren't inherited")
  func computedValues() throws {
    let rect = try #require(
      style(
        of: "r",
        in: "<style>rect { transition: fill 1s, opacity 1s }</style>"
          + #"<g style="transition-delay: 2s"><rect id="r" style="transition-duration: 2s, 3s"/></g>"#))
    #expect(rect.transitionProperty == [.property(.fill), .property(.opacity)])
    #expect(rect.transitionDuration == [2, 3])
    #expect(rect.transitionTimingFunction == [.ease, .ease])
    #expect(rect.transitionDelay == [0, 0])
    #expect(rect.transitionBehavior == [.normal, .normal])
    #expect(ComputedStyle.initial.transitionProperty == [.all])
  }

  @Test("keyframes leave out the properties of transitions, which animations don't change")
  func notAnimatable() throws {
    let sheet = stylesheet("@keyframes a { to { opacity: 0; transition-duration: 5s } }")
    let keyframe = try #require(sheet.keyframes["a"]?.keyframes.first)
    #expect(keyframe.declarations.declared(OpacityProperty.self) == 0)
    #expect(keyframe.declarations[TransitionDurationProperty.self] == nil)
    #expect(PropertyID.allCases.filter { !$0.isAnimatable }.count == 13)
    #expect(PropertyID.transitionBehavior.isTransition && !PropertyID.opacity.isTransition)
  }
}
