import Foundation
import Testing
import _CSSParser
import _SelectorParser

@testable import SVGCore

func matchesSelector(element: ElementCursor, css: String) -> Bool {
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
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": "foo"]))
    #expect(matchesSelector(element: rect, css: "rect"))
  }

  @Test("match type selector - no match")
  func matchTypeSelectorNoMatch() {
    let rect = ElementCursor(root: documentElement(0, "rect"))
    #expect(!matchesSelector(element: rect, css: "circle"))
  }

  @Test("match class selector")
  func matchClassSelector() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": "foo"]))
    #expect(matchesSelector(element: rect, css: ".foo"))
  }

  @Test("match class selector - no match")
  func matchClassSelectorNoMatch() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": "foo"]))
    #expect(!matchesSelector(element: rect, css: ".bar"))
  }

  @Test("match each class of an element with several classes", arguments: [".foo", ".bar", ".foo.bar", "rect.bar"])
  func matchClassInList(css: String) {
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": " foo\tbar\n"]))
    #expect(matchesSelector(element: rect, css: css))
  }

  @Test("match class selector - no match for part of a class name")
  func matchClassSelectorNoMatchForPart() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": "foo bar"]))
    #expect(!matchesSelector(element: rect, css: ".fo"))
    #expect(!matchesSelector(element: rect, css: ".foo\\ bar"))
  }

  @Test("match id selector")
  func matchIdSelector() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["id": "main"]))
    #expect(matchesSelector(element: rect, css: "#main"))
  }

  @Test("match id selector - no match")
  func matchIdSelectorNoMatch() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["id": "main"]))
    #expect(!matchesSelector(element: rect, css: "#other"))
  }

  @Test("match universal selector")
  func matchUniversalSelector() {
    let rect = ElementCursor(root: documentElement(0, "rect"))
    #expect(matchesSelector(element: rect, css: "*"))
  }

  @Test("match compound selector")
  func matchCompoundSelector() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": "foo", "id": "bar"]))
    #expect(matchesSelector(element: rect, css: "rect.foo#bar"))
  }

  @Test("match compound selector - partial match fails")
  func matchCompoundSelectorNoMatch() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["class": "foo"]))
    #expect(!matchesSelector(element: rect, css: "rect.foo#bar"))
  }

  @Test("match child combinator")
  func matchChildCombinator() {
    let parent = documentElement(0, "g", ["class": "parent"], [documentElement(1, "rect", ["class": "foo"])])
    let rect = ElementCursor(root: parent).child(at: 0)
    #expect(rect.parent?.element.id == parent.id)
    #expect(matchesSelector(element: rect, css: "g.parent > rect"))
  }

  @Test("match child combinator - no match (not direct child)")
  func matchChildCombinatorNoMatch() {
    let grandParent = documentElement(
      0, "svg", ["class": "grand-parent"],
      [documentElement(1, "g", ["class": "parent"], [documentElement(2, "rect", ["class": "foo"])])])
    let rect = ElementCursor(root: grandParent).child(at: 0).child(at: 0)
    #expect(rect.parent?.element.id == ElementID(rawValue: 1))
    #expect(rect.parent?.parent?.element.id == grandParent.id)
    #expect(!matchesSelector(element: rect, css: "svg.grand-parent > rect"))
  }

  @Test("match descendant combinator")
  func matchDescendantCombinator() {
    let grandParent = documentElement(
      0, "svg", ["class": "grand-parent"],
      [documentElement(1, "g", ["class": "parent"], [documentElement(2, "rect", ["class": "foo"])])])
    let rect = ElementCursor(root: grandParent).child(at: 0).child(at: 0)
    #expect(matchesSelector(element: rect, css: "svg.grand-parent rect"))
  }

  @Test("match next sibling combinator")
  func matchNextSiblingCombinator() {
    let parent = documentElement(0, "g", [:], [documentElement(1, "circle"), documentElement(2, "rect")])
    let rect = ElementCursor(root: parent).child(at: 1)
    #expect(rect.prevSibling?.element.id == ElementID(rawValue: 1))
    #expect(rect.prevSibling?.nextSibling?.element.id == ElementID(rawValue: 2))
    #expect(matchesSelector(element: rect, css: "circle + rect"))
  }

  @Test("match later sibling combinator")
  func matchLaterSiblingSelector() {
    let parent = documentElement(
      0, "g", [:], [documentElement(1, "circle"), documentElement(2, "path"), documentElement(3, "rect")])
    let rect = ElementCursor(root: parent).child(at: 2)
    #expect(matchesSelector(element: rect, css: "circle ~ rect"))
  }

  @Test("an element that SVGUIView doesn't render is a sibling for selectors")
  func unknownElementIsSibling() {
    let parent = documentElement(
      0, "g", [:], [documentElement(1, "rect"), documentElement(2, "foo"), documentElement(3, "rect")])
    let rect = ElementCursor(root: parent).child(at: 2)
    #expect(!matchesSelector(element: rect, css: "rect + rect"))
    #expect(matchesSelector(element: rect, css: "foo + rect"))
    #expect(matchesSelector(element: rect, css: "rect ~ rect"))
  }

  @Test("an element that SVGUIView doesn't render is an ancestor for selectors")
  func unknownElementIsAncestor() {
    let root = documentElement(0, "svg", [:], [documentElement(1, "a", [:], [documentElement(2, "rect")])])
    let rect = ElementCursor(root: root).child(at: 0).child(at: 0)
    #expect(!matchesSelector(element: rect, css: "svg > rect"))
    #expect(matchesSelector(element: rect, css: "a > rect"))
    #expect(matchesSelector(element: rect, css: "svg rect"))
  }
}
