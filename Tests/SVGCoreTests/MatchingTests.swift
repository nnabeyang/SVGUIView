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

  /// The tree that the tables of selectors match:
  ///
  /// ```
  /// <svg id="0">
  ///   <g id="1" class="a">
  ///     <rect id="2" x="1" class="p q" lang="en-US"/>
  ///     <circle id="3"/>
  ///     <rect id="4" x="10"/>
  ///   </g>
  ///   <g id="5"/>
  ///   <text id="6">hi</text>
  /// </svg>
  /// ```
  private static let tree = DocumentElement(
    id: ElementID(rawValue: 0), name: .svg, localName: "svg", attributes: [:], text: "",
    children: [
      documentElement(
        1, "g", ["class": "a"],
        [
          documentElement(2, "rect", ["x": "1", "class": "p q", "lang": "en-US"]),
          documentElement(3, "circle"),
          documentElement(4, "rect", ["x": "10"]),
        ]),
      documentElement(5, "g"),
      DocumentElement(
        id: ElementID(rawValue: 6), name: .text, localName: "text", attributes: [:], text: "hi", children: []),
    ])

  /// The identifiers of the elements of the tree that a selector matches.
  private static func matches(_ css: String) -> Set<Int> {
    func visit(_ cursor: ElementCursor) -> [Int] {
      (matchesSelector(element: cursor, css: css) ? [cursor.element.id.rawValue] : [])
        + cursor.children.flatMap(visit)
    }
    return Set(visit(ElementCursor(root: tree)))
  }

  @Test(
    "attribute selectors",
    arguments: [
      ("rect[x]", [2, 4]), (#"rect[x="1"]"#, [2]), (#"[x^="1"]"#, [2, 4]), (#"[x$="0"]"#, [4]),
      (#"[x*="0"]"#, [4]), (#"[class~="q"]"#, [2]), (#"[class~="p q"]"#, []), (#"[class~=""]"#, []),
      (#"[lang|="en"]"#, [2]), (#"[lang|="en-U"]"#, []), (#"[x="1" i]"#, [2]), (#"[X="1"]"#, []),
      ("g > rect[x] + circle", [3]),
    ] as [(String, Set<Int>)])
  func attributeSelectors(css: String, expected: Set<Int>) {
    #expect(Self.matches(css) == expected)
  }

  @Test(
    "pseudo-classes of the structure of the tree",
    arguments: [
      (":root", [0]), ("rect:first-child", [2]), (":last-child", [0, 4, 6]), ("g > :nth-child(2)", [3]),
      ("g > :nth-child(odd)", [2, 4]), ("g > :nth-last-child(1)", [4]), ("rect:nth-of-type(2)", [4]),
      ("rect:last-of-type", [4]), ("circle:only-of-type", [3]), ("g :only-child", []), ("g:empty", [5]),
      ("text:empty", []),
    ] as [(String, Set<Int>)])
  func structuralPseudoClasses(css: String, expected: Set<Int>) {
    #expect(Self.matches(css) == expected)
  }

  @Test(
    "selectors in :not(), :is() and :where()",
    arguments: [
      (#"rect:not([x="1"])"#, [4]), ("g > :not(rect, circle)", []), (#":is(circle, [x="10"])"#, [3, 4]),
      (":where(.a) rect", [2, 4]), ("rect:not(:first-child)", [4]),
    ] as [(String, Set<Int>)])
  func nestedSelectors(css: String, expected: Set<Int>) {
    #expect(Self.matches(css) == expected)
  }

  @Test(
    "a selector with a part that matching doesn't support matches no element",
    arguments: ["rect:hover", ":focus", "g:active rect", "a:visited", "rect:hover + circle"])
  func unsupportedSelector(css: String) {
    #expect(Self.matches(css).isEmpty)
  }

  /// A tree of languages and links for `:lang()`, `:link` and `:any-link`:
  ///
  /// ```svg
  /// <svg id="0" lang="en">
  ///   <g id="1" xml:lang="fr" lang="en">
  ///     <rect id="2"/>
  ///     <text id="3" lang="FR-ca"/>
  ///   </g>
  ///   <a id="4" href="#x"/>
  ///   <a id="5"/>
  ///   <rect id="6" lang=""/>
  ///   <circle id="7" href="#x"/>
  /// </svg>
  /// ```
  private static let languagesAndLinks = documentElement(
    0, "svg", ["lang": "en"],
    [
      documentElement(
        1, "g", ["xml:lang": "fr", "lang": "en"], [documentElement(2, "rect"), documentElement(3, "text", ["lang": "FR-ca"])]),
      documentElement(4, "a", ["href": "#x"]),
      documentElement(5, "a"),
      documentElement(6, "rect", ["lang": ""]),
      documentElement(7, "circle", ["href": "#x"]),
    ])

  @Test(
    ":lang() matches the language of the element or of its nearest ancestor that has one, and :link and :any-link match links",
    arguments: [
      (":lang(en)", [0, 4, 5, 7]), (":lang(EN)", [0, 4, 5, 7]), (":lang(fr)", [1, 2, 3]), (":lang(fr-ca)", [3]),
      (":lang(e)", []), (":lang(en-US)", []), ("rect:not(:lang(en))", [2, 6]), ("a:link", [4]), (":any-link", [4]),
      (":link + a", [5]),
    ] as [(String, Set<Int>)])
  func languagesAndLinks(css: String, expected: Set<Int>) {
    func visit(_ cursor: ElementCursor) -> [Int] {
      (matchesSelector(element: cursor, css: css) ? [cursor.element.id.rawValue] : []) + cursor.children.flatMap(visit)
    }
    #expect(Set(visit(ElementCursor(root: Self.languagesAndLinks))) == expected)
  }

  @Test("style sheets match xml:lang and xlink:href of a document, and changes of lang and href")
  func languagesAndLinksInDocument() throws {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100">"#
      + "<style>:lang(fr) { fill: blue } a:any-link rect { stroke: green }</style>"
      + #"<g id="g" xml:lang="fr"><rect id="r" width="10" height="10"/></g>"#
      + ##"<a id="a" xlink:href="#r"><rect id="s" width="10" height="10"/></a></svg>"##
    let base = SVGParser.parse(data: Data(svg.utf8))
    func element(_ id: String, in base: SVGBaseContext) -> (any SVGElement)? {
      base.root?.elements.first { $0.base.id == id }
    }
    #expect(try #require(element("r", in: base)).style.fill == Paint("blue"))
    #expect(try #require(element("s", in: base)).style.stroke == Paint("green"))
    let g = try #require(base.document.element(id: "g"))
    let a = try #require(base.document.element(id: "a"))
    let changed = base.changingAttributes([g: ["xml:lang": "en"], a: ["href": nil]])
    #expect(try #require(element("r", in: changed)).style.fill != Paint("blue"))
    #expect(try #require(element("s", in: changed)).style.stroke != Paint("green"))
  }

  @Test("a selector list matches with the selectors that matching supports")
  func listWithUnsupportedSelector() {
    let rect = ElementCursor(root: documentElement(0, "rect", ["x": "1"]))
    #expect(matchesSelector(element: rect, css: "rect:hover, rect"))
  }
}
