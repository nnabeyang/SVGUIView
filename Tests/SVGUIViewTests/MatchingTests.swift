import Foundation
import Testing
import _CSSParser
import _SelectorParser

@testable import SVGUIView

func matchesSelector(element: some SVGDrawableElement, css: String) -> Bool {
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
    #expect(matchesSelector(element: element, css: "rect"))
  }

  @Test("match type selector - no match")
  func matchTypeSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: [:])
    #expect(!matchesSelector(element: element, css: "circle"))
  }

  @Test("match class selector")
  func matchClassSelector() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    #expect(matchesSelector(element: element, css: ".foo"))
  }

  @Test("match class selector - no match")
  func matchClassSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    #expect(matchesSelector(element: element, css: ".foo"))
  }

  @Test("match id selector")
  func matchIdSelector() {
    let element = SVGRectElement(text: "", attributes: ["id": "main"])
    #expect(matchesSelector(element: element, css: "#main"))
  }

  @Test("match id selector - no match")
  func matchIdSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: ["id": "main"])
    #expect(!matchesSelector(element: element, css: "#other"))
  }

  @Test("match universal selector")
  func matchUniversalSelector() {
    let element = SVGRectElement(text: "", attributes: [:])
    #expect(matchesSelector(element: element, css: "*"))
  }

  @Test("match compound selector")
  func matchCompoundSelector() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo", "id": "bar"])
    #expect(matchesSelector(element: element, css: "rect.foo#bar"))
  }

  @Test("match compound selector - partial match fails")
  func matchCompoundSelectorNoMatch() {
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    #expect(!matchesSelector(element: element, css: "rect.foo#bar"))
  }
}
