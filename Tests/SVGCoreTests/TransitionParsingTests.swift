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

  @Test("the computed values are the lists that the cascade gives, and the initial values aren't inherited")
  func computedValues() throws {
    let rect = try #require(
      style(
        of: "r",
        in: "<style>rect { transition-property: fill, opacity; transition-duration: 1s }</style>"
          + #"<g style="transition-delay: 2s"><rect id="r" style="transition-duration: 2s, 3s"/></g>"#))
    #expect(rect.transitionProperty == [.property(.fill), .property(.opacity)])
    #expect(rect.transitionDuration == [2, 3])
    #expect(rect.transitionTimingFunction == [.ease])
    #expect(rect.transitionDelay == [0])
    #expect(rect.transitionBehavior == [.normal])
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
