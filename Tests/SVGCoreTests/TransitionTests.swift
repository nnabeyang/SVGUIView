import Foundation
import Testing

@testable import SVGCore

/// The resolver of an element whose `color` is lime.
private let resolver: StyleResolver = {
  var style = ComputedStyle.initial
  style.color = SVGAttributeScanner.parseColor(description: "lime")!
  return StyleResolver(style: style, parent: .initial, root: .initial)
}()

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
}
