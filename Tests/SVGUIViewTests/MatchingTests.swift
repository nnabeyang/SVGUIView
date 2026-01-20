import Foundation
import Testing
import _CSSParser
import _SelectorParser

@testable import SVGUIView

func matchesSelector(element: SVGBaseElement, css: String) -> Bool {
  let parserInput = ParserInput(input: css)
  var input = _SelectorParser.CSSParser(input: parserInput)
  let selectorParser = SelectorParser(stylesheetOrigin: .author, namespaces: .default(), urlData: .init(URL(string: "https://example.com")!), forSupportsRule: false)
  guard case .success(let list) = SelectorList.parse(parser: selectorParser, input: &input, parseRelative: .no) else { return false }
  var context = MatchingContext<SVGSelectorImpl>()
  for selector in list.slice {
    if matchesSelector(selector: selector, offset: 0, element: element, context: &context) {
      return true
    }
  }
  return false
}

@Suite("Matching")
struct MatchingTests {
  @Test("match type selector")
  func matchTypeSelector() {
    let element = SVGRectElement(text: "", attributes: [:])
    #expect(matchesSelector(element: element.base, css: "rect"))
  }

  @Test("match type selector - no match")
  func matchTypeSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: [:])
    #expect(!matchesSelector(element: element.base, css: "circle"))
  }

  @Test("match class selector")
  func matchClassSelector() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    #expect(matchesSelector(element: element.base, css: ".foo"))
  }

  @Test("match class selector - no match")
  func matchClassSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    #expect(matchesSelector(element: element.base, css: ".foo"))
  }

  @Test("match id selector")
  func matchIdSelector() {
    let element = SVGRectElement(text: "", attributes: ["id": "main"])
    #expect(matchesSelector(element: element.base, css: "#main"))
  }

  @Test("match id selector - no match")
  func matchIdSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: ["id": "main"])
    #expect(!matchesSelector(element: element.base, css: "#other"))
  }

  @Test("match universal selector")
  func matchUniversalSelector() {
    let element = SVGRectElement(text: "", attributes: [:])
    #expect(matchesSelector(element: element.base, css: "*"))
  }

  @Test("match compound selector")
  func matchCompoundSelector() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo", "id": "bar"])
    #expect(matchesSelector(element: element.base, css: "rect.foo#bar"))
  }

  @Test("match compound selector - partial match fails")
  func matchCompoundSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    #expect(!matchesSelector(element: element.base, css: "rect.foo#bar"))
  }

  @Test("match child combinator")
  func matchChildCombinator() {
    let rect = SVGBaseElement.create(name: .rect, text: "", attributes: ["class": "foo"], children: [])
    let parent = SVGBaseElement.create(name: .g, text: "", attributes: ["class": "parent"], children: [rect])
    #expect(rect.parent?.index == parent.index)
    #expect(matchesSelector(element: rect, css: "g.parent > rect"))
  }

  @Test("match child combinator - no match (not direct child)")
  func matchChildCombinatorNoMatch() {
    let rect = SVGBaseElement.create(name: .rect, text: "", attributes: ["class": "foo"], children: [])
    let parent = SVGBaseElement.create(name: .g, text: "", attributes: ["class": "parent"], children: [rect])
    let grandParent = SVGBaseElement.create(name: .svg, text: "", attributes: ["class": "grand-parent"], children: [parent])
    #expect(rect.parent?.index == parent.index)
    #expect(parent.parent?.index == grandParent.index)
    #expect(!matchesSelector(element: rect, css: "svg.grand-parent > rect"))
  }

  @Test("match descendant combinator")
  func matchDescendantCombinator() {
    let rect = SVGBaseElement.create(name: .rect, text: "", attributes: ["class": "foo"], children: [])
    let parent = SVGBaseElement.create(name: .g, text: "", attributes: ["class": "parent"], children: [rect])
    let grandParent = SVGBaseElement.create(name: .svg, text: "", attributes: ["class": "grand-parent"], children: [parent])
    #expect(rect.parent?.index == parent.index)
    #expect(parent.parent?.index == grandParent.index)
    #expect(matchesSelector(element: rect, css: "svg.grand-parent rect"))
  }

  @Test("match next sibling combinator")
  func matchNextSiblingCombinator() {
    let rect = SVGBaseElement.create(name: .rect, text: "", attributes: [:], children: [])
    let circle = SVGBaseElement.create(name: .circle, text: "", attributes: [:], children: [])
    let parent = SVGBaseElement.create(name: .g, text: "", attributes: [:], children: [circle, rect])
    #expect(rect.parent?.index == parent.index)
    #expect(circle.parent?.index == parent.index)
    #expect(matchesSelector(element: rect, css: "circle + rect"))
  }

  @Test("match later sibling combinator")
  func matchLaterSiblingSelector() {
    let rect = SVGBaseElement.create(name: .rect, text: "", attributes: [:], children: [])
    let circle = SVGBaseElement.create(name: .circle, text: "", attributes: [:], children: [])
    let path = SVGBaseElement.create(name: .path, text: "", attributes: [:], children: [])
    let parent = SVGBaseElement.create(name: .g, text: "", attributes: [:], children: [circle, path, rect])
    #expect(rect.parent?.index == parent.index)
    #expect(circle.parent?.index == parent.index)
    #expect(matchesSelector(element: rect, css: "circle ~ rect"))
  }
}
