import Foundation
import Testing
import _CSSParser
import _SelectorParser

@testable import SVGCore

/// A declaration for the tests of the order of the cascade, whose property doesn't matter.
private func declaration(_ importance: Importance, _ specificity: Specificity, _ sourceOrder: Int) -> CSSDeclaration {
  CSSDeclaration(
    declaration: PropertyDeclaration(FillOpacityProperty.self, .value(Double(sourceOrder))), importance: importance,
    specificity: specificity, sourceOrder: sourceOrder)
}

private func stylesheet(_ css: String) -> Stylesheet {
  let input = _SelectorParser.CSSParser(input: ParserInput(input: css))
  var parser = CSSParser(input: input)
  return parser.parse()
}

/// The name of the color that the cascade gives `fill`.
private func fill(_ cascaded: CascadedValues) -> String? {
  guard case .color(let color) = cascaded.declared(FillProperty.self) else { return nil }
  return color.description
}

@Suite("Cascade")
struct CascadeTests {
  @Test("compare declarations - same origin, different specificity")
  func compareDeclSpecificity() {
    let element = declaration(.normal, .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1), 0)
    let classLike = declaration(.normal, .init(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0), 0)
    #expect(classLike > element)
  }

  @Test("compare declarations - same specificity, different source order")
  func compareDeclSourceOrder() {
    let first = declaration(.normal, .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1), 1)
    let second = declaration(.normal, .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1), 2)
    #expect(second > first)
  }

  @Test("compare declarations - important beats normal")
  func compareDeclImportance() {
    let normal = declaration(.normal, .init(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0), 1)
    let important = declaration(.important, .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1), 2)
    #expect(important > normal)
  }

  @Test("the cascade keeps which properties important declarations win, and the document keeps its keyframes")
  func importantProperties() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg">
        <style>
          rect { fill: red !important; opacity: 0.5 }
          @keyframes spin { to { opacity: 1 } }
        </style>
        <rect id="r" style="fill: blue; opacity: 1; stroke: red !important" fill-opacity="0.5"/>
      </svg>
      """#
    let base = SVGParser.parse(data: Data(svg.utf8))
    let rect = try #require(base["r"])
    #expect(rect.base.cascaded.important == [PropertyID.fill, .stroke])
    #expect(base.animations.keyframes["spin"]?.keyframes.count == 1)
  }

  @Test("of equal declarations, the later one comes later")
  func sortKeepsOrderOfEqualDeclarations() {
    let specificity = Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1)
    let first = CSSDeclaration(
      declaration: PropertyDeclaration(FillOpacityProperty.self, .value(0.1)), importance: .normal,
      specificity: specificity, sourceOrder: 0)
    let second = CSSDeclaration(
      declaration: PropertyDeclaration(FillOpacityProperty.self, .value(0.2)), importance: .normal,
      specificity: specificity, sourceOrder: 0)
    let cascaded = CascadedValues(sortedByPrecedence([first, second]).map(\.declaration))
    #expect(cascaded.declared(FillOpacityProperty.self) == 0.2)
  }

  @Test("style sheets override presentation attributes, even with the universal selector")
  func stylesheetBeatsAttributes() {
    let element = ElementCursor(root: documentElement(0, "rect", ["fill": "red"]))
    #expect(fill(cascade(element: element, stylesheet: stylesheet("* { fill: blue; }"))) == "blue")
    #expect(fill(cascade(element: element, stylesheet: stylesheet("circle { fill: blue; }"))) == "red")
  }

  @Test("the style attribute overrides style sheets, and important declarations override it")
  func inlineStyle() {
    let element = ElementCursor(root: documentElement(0, "rect", ["id": "a", "style": "fill: green"]))
    #expect(fill(cascade(element: element, stylesheet: stylesheet("#a { fill: blue; }"))) == "green")
    #expect(fill(cascade(element: element, stylesheet: stylesheet("rect { fill: blue !important; }"))) == "blue")
    let important = ElementCursor(root: documentElement(0, "rect", ["style": "fill: green !important"]))
    #expect(fill(cascade(element: important, stylesheet: stylesheet("rect { fill: blue !important; }"))) == "green")
  }

  @Test("an invalid declaration doesn't override a valid one")
  func invalidDeclaration() {
    let element = ElementCursor(root: documentElement(0, "rect", ["opacity": "0.5"]))
    let cascaded = cascade(element: element, stylesheet: stylesheet("rect { opacity: foo; }"))
    #expect(cascaded.declared(OpacityProperty.self) == 0.5)
  }

  @Test("stylesheet match and cascade")
  func stylesheetMatchAndCascade() {
    let element = ElementCursor(root: documentElement(0, "rect", ["class": "foo"]))
    let cascaded = cascade(element: element, stylesheet: stylesheet("rect.foo { width: 100px;}"))
    #expect(cascaded.declared(WidthProperty.self) == .pixel(100))
  }

  @Test("stylesheet - non-matching element")
  func stylesheetNonMatchingElement() {
    let element = ElementCursor(root: documentElement(0, "rect", ["class": "foo"]))
    let cascaded = cascade(element: element, stylesheet: stylesheet("rect.bar { width: 100px;}"))
    #expect(cascaded.declared(WidthProperty.self) == nil)
  }

  @Test("specificity - ID beats class")
  func stylesheetIdBeatsClass() {
    let css = #"""
      #main { width: 200px;}
      .container { width: 100px;}
      """#
    let element = ElementCursor(root: documentElement(0, "rect", ["class": "container", "id": "main"]))
    #expect(cascade(element: element, stylesheet: stylesheet(css)).declared(WidthProperty.self) == .pixel(200))
  }

  @Test("rules of a later style element win over equal rules of an earlier one")
  func laterStyleElementWins() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg">
        <style>rect { fill: red; }</style>
        <style>rect { fill: blue; }</style>
        <rect width="10" height="10"/>
      </svg>
      """#
    let context = SVGParser.parse(data: Data(svg.utf8))
    let rect = try #require(context.root?.children.first as? SVGRectElement)
    guard case .color(let color) = rect.style.fill else {
      Issue.record("fill isn't a color")
      return
    }
    #expect(color.description == "blue")
  }

  @Test("specificity - combined selectors")
  func stylesheetCombinedSelectors() {
    let css = #"""
      rect.highlight { fill: blue;}
      rect { fill: red;}
      """#
    let element = ElementCursor(root: documentElement(0, "rect", ["class": "highlight"]))
    #expect(fill(cascade(element: element, stylesheet: stylesheet(css))) == "blue")
  }
}
