import Testing
import _CSSParser
import _SelectorParser

@testable import SVGUIView

@Suite("Cascade")
struct CascadeTests {
  @Test("compare declarations - same origin, different specificity")
  func compareDeclSpecificity() {
    let declElement = CSSDeclaration(
      type: .fillOpacity,
      value: .number(1),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 0)
    let declClass = CSSDeclaration(
      type: .fillOpacity,
      value: .number(1),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
      sourceOrder: 0)
    #expect(declClass > declElement)
  }

  @Test("compare declarations - same specificity, different source order")
  func compareDeclSourceOrder() {
    let declFirst = CSSDeclaration(
      type: .fillOpacity,
      value: .number(1),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 1)
    let declSecond = CSSDeclaration(
      type: .fillOpacity,
      value: .number(1),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 2)
    #expect(declSecond > declFirst)
  }

  @Test("compare declarations - important beats normal")
  func compareDeclImportance() {
    let declNormal = CSSDeclaration(
      type: .fillOpacity,
      value: .number(1),
      importance: .normal,
      specificity: .init(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0),
      sourceOrder: 1)
    let declImportant = CSSDeclaration(
      type: .fillOpacity,
      value: .number(1),
      importance: .important,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 2)
    #expect(declImportant > declNormal)
  }

  @Test("cascade - single declaration")
  func cascadeSingleDeclaration() {
    let decl = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 100, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 0)
    let result = cascade([decl])
    #expect(result[.width] == .length(.init(value: 100, unit: .px)))
  }

  @Test("cascade - later declaration wins")
  func cascadeLaterDeclarationWins() {
    let decl1 = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 100, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 1)
    let decl2 = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 200, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 2)
    let result = cascade([decl1, decl2])
    #expect(result[.width] == .length(.init(value: 200, unit: .px)))
  }

  @Test("cascade - higher specificity wins")
  func cascadeHigherSpecificityDeclarationWins() {
    let declClass = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 100, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
      sourceOrder: 1)
    let declElement = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 200, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 2)
    let result = cascade([declClass, declElement])
    #expect(result[.width] == .length(.init(value: 100, unit: .px)))
  }

  @Test("cascade - important wins")
  func cascadeImportantDeclarationWins() {
    let declImportant = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 100, unit: .px)),
      importance: .important,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 1)
    let declNormal = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 200, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0),
      sourceOrder: 10)
    let result = cascade([declImportant, declNormal])
    #expect(result[.width] == .length(.init(value: 100, unit: .px)))
  }

  @Test("cascade - multiple properties")
  func cascadeMultipleProperties() {
    let decl1 = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 100, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
      sourceOrder: 1)
    let decl2 = CSSDeclaration(
      type: .height,
      value: .length(.init(value: 50, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
      sourceOrder: 2)
    let decl3 = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 200, unit: .px)),
      importance: .important,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 3)

    let result = cascade([decl1, decl2, decl3])
    #expect(result[.width] == .length(.init(value: 200, unit: .px)))
    #expect(result[.height] == .length(.init(value: 50, unit: .px)))
  }

  @Test("collect declarations - inline beats rules")
  func collectDeclarationsInlineBeatsRules() {
    let decl1 = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 100, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0),
      sourceOrder: 1)
    let decl2 = CSSDeclaration(
      type: .width,
      value: .length(.init(value: 200, unit: .px)),
      importance: .normal,
      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
      sourceOrder: 1)
    let ruleMatch = RuleMatch(
      specificity: .init(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0),
      declarations: [decl1],
      sourceOrder: 0)
    let collected = collectDeclarations(matches: [ruleMatch], inlineStyle: [decl2])
    let result = cascade(collected)
    #expect(result[.width] == .length(.init(value: 200, unit: .px)))
  }

  @Test("stylesheet match and cascade")
  func stylesheetMatchAndCascade() {
    let parserInput = ParserInput(input: "rect.foo { width: 100px;}")
    let input = _SelectorParser.CSSParser(input: parserInput)
    var parser = CSSParser(input: input)
    let stylesheet: Stylesheet = parser.parse()
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    let result = cascadeElement(element: element.base, stylesheets: [stylesheet], inlineStyle: [])
    #expect(result[.width] == .length(.init(value: 100, unit: .px)))
  }

  @Test("stylesheet - non-matching element")
  func stylesheetNonMatchingElement() throws {
    let parserInput = ParserInput(input: "rect.bar { width: 100px;}")
    let input = _SelectorParser.CSSParser(input: parserInput)
    var parser = CSSParser(input: input)
    let stylesheet: Stylesheet = parser.parse()
    let element = SVGRectElement(text: "", attributes: ["class": "foo"])
    let result = cascadeElement(element: element.base, stylesheets: [stylesheet], inlineStyle: [])
    #expect(result[.width] == nil)
  }

  @Test("specificity - ID beats class")
  func stylesheetIdBeatsClass() throws {
    let css = #"""
      .container { width: 100px;}
      #main { width: 200px;}
      """#
    let parserInput = ParserInput(input: css)
    let input = _SelectorParser.CSSParser(input: parserInput)
    var parser = CSSParser(input: input)
    let stylesheet: Stylesheet = parser.parse()
    let element = SVGRectElement(text: "", attributes: ["class": "container", "id": "main"])
    let result = cascadeElement(element: element.base, stylesheets: [stylesheet], inlineStyle: [])
    #expect(result[.width] == .length(.init(value: 200, unit: .px)))
  }

  @Test("specificity - combined selectors")
  func stylesheetCombinedSelectors() throws {
    let css = #"""
      rect { fill: red;}
      rect.highlight { fill: blue;}
      """#
    let parserInput = ParserInput(input: css)
    let input = _SelectorParser.CSSParser(input: parserInput)
    var parser = CSSParser(input: input)
    let stylesheet: Stylesheet = parser.parse()
    let element = SVGRectElement(text: "", attributes: ["class": "highlight"])
    let result = cascadeElement(element: element.base, stylesheets: [stylesheet], inlineStyle: [])
    #expect(result[.fill] == .fill(.color(.named(.init(name: "blue")))))
  }
}
