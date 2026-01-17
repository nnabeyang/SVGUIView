import Foundation
import Testing
import _CSSParser

@testable import _SelectorParser

@Suite("SelectorParser")
struct SelectorParserTests {
  @Test("visitor sees pseudo classes in :not and ::before:hover")
  func visitor() throws {
    do {
      var testVisitor = TestVisitor(seen: [])
      let list = try parse(input: ":not(:hover) ~ label").get()
      let selector = list.slice[0]
      _ = selector.visit(&testVisitor)
      #expect(testVisitor.seen.contains(":hover"))
    }
    do {
      var testVisitor = TestVisitor(seen: [])
      let list = try parse(input: "::before:hover").get()
      let selector = list.slice[0]
      _ = selector.visit(&testVisitor)
      #expect(testVisitor.seen.contains(":hover"))
    }
  }

  private static let nsSVG: DummyAtom = "http://www.w3.org/2000/svg"
  private static let nsMATHML: DummyAtom = "http://www.w3.org/1998/Math/MathML"
  @Test("parses :empty successfully")
  func empty() {
    let parserInput = ParserInput(input: ":empty")
    var input = CSSParser(input: parserInput)
    let list = SelectorList.parse(
      parser: DummyParser.default(),
      input: &input,
      parseRelative: .no)
    guard case .success = list else {
      Issue.record("Expected to parse successfully")
      return
    }
  }

  @Test("parsing various selectors succeeds or fails as expected")
  func parsing() {
    #expect(parse(input: "").isFailure)
    #expect(parse(input: ":lang(4)").isFailure)
    #expect(parse(input: ":lang(en US)").isFailure)
    #expect(
      parse(input: "EeÉ")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .localName(.init(name: "EeÉ", lowerName: "eeÉ"))
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "|e")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitNoNamespace,
                .localName(.init(name: "e", lowerName: "e")),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ])))
    #expect(
      parseExpected(input: "*|e", expected: "e")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .localName(.init(name: "e", lowerName: "e"))
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "*|e", parser: DummyParser.defaultWithNamespace(defaultNS: "https://example.com"))
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitAnyNamespace,
                .localName(.init(name: "e", lowerName: "e")),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "*")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitUniversalType
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "|*")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitNoNamespace,
                .explicitUniversalType,
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseExpected(input: "*|*", expected: "*")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitUniversalType
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "*|*", parser: DummyParser.defaultWithNamespace(defaultNS: "https://example.com"))
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitAnyNamespace,
                .explicitUniversalType,
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: ".foo:lang(en-US)")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .class("foo"),
                .nonTSPseudoClass(.lang("en-US")),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 2, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "#bar")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .id("bar")
              ],
              specificity: Specificity(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "e.foo#bar")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .localName(.init(name: "e", lowerName: "e")),
                .class("foo"),
                .id("bar"),
              ],
              specificity: Specificity(idSelectors: 1, classLikeSelectors: 1, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "e.foo #bar")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .localName(.init(name: "e", lowerName: "e")),
                .class("foo"),
                .combinator(.descendant),
                .id("bar"),
              ],
              specificity: Specificity(idSelectors: 1, classLikeSelectors: 1, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "[Foo]", parser: DummyParser.default())
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .attributeInNoNamespaceExists(localName: "Foo", localNameLower: "foo")
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(parseNS(input: "svg|circle", parser: DummyParser.default()).isFailure)
    var parser = DummyParser.default()
    parser.nsPrefixes["svg"] = Self.nsSVG
    #expect(
      parseNS(input: "svg|circle", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .namespace(prefix: "svg", url: Self.nsSVG),
                .localName(.init(name: "circle", lowerName: "circle")),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "svg|*", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .namespace(prefix: "svg", url: Self.nsSVG),
                .explicitUniversalType,
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    parser.defaultNS = Self.nsMATHML
    #expect(
      parseNS(input: "[Foo]", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .defaultNamespace(url: Self.nsMATHML),
                .attributeInNoNamespaceExists(localName: "Foo", localNameLower: "foo"),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "e", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .defaultNamespace(url: Self.nsMATHML),
                .localName(.init(name: "e", lowerName: "e")),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "*", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .defaultNamespace(url: Self.nsMATHML),
                .explicitUniversalType,
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: "*|*", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .explicitAnyNamespace,
                .explicitUniversalType,
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: ":not(.cl)", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .defaultNamespace(url: Self.nsMATHML),
                .negation(
                  .init(slice: [
                    .init(
                      slice: [.class("cl")],
                      specificity: .init(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
                      flags: .empty)
                  ])),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: ":not(*)", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .defaultNamespace(url: Self.nsMATHML),
                .negation(
                  .init(slice: [
                    .init(
                      slice: [
                        .defaultNamespace(url: Self.nsMATHML),
                        .explicitUniversalType,
                      ],
                      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
                      flags: .empty)
                  ])),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: ":not(e)", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .defaultNamespace(url: Self.nsMATHML),
                .negation(
                  .init(slice: [
                    .init(
                      slice: [
                        .defaultNamespace(url: Self.nsMATHML),
                        .localName(.init(name: "e", lowerName: "e")),
                      ],
                      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
                      flags: .empty)
                  ])),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "[attr|=\"foo\"]")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .attributeInNoNamespace(
                  localName: "attr",
                  operator: .dashMatch,
                  value: "foo",
                  caseSensitivity: .caseSensitive)
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parse(input: "::before")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .combinator(.pseudoElement),
                .pseudoElement(.before),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
              flags: .hasPseudo)
          ]
          )))
    #expect(
      parse(input: "::before:hover")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .combinator(.pseudoElement),
                .pseudoElement(.before),
                .nonTSPseudoClass(.hover),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 1),
              flags: .hasPseudo)
          ]
          )))
    #expect(
      parse(input: "::before:hover:hover")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .combinator(.pseudoElement),
                .pseudoElement(.before),
                .nonTSPseudoClass(.hover),
                .nonTSPseudoClass(.hover),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 2, elementSelectors: 1),
              flags: .hasPseudo)
          ]
          )))
    #expect(parse(input: "::before:hover:lang(foo)").isFailure)
    #expect(parse(input: "::before:hover .foo").isFailure)
    #expect(parse(input: "::before .foo").isFailure)
    #expect(parse(input: "::before ~ bar").isFailure)
    #expect(!parse(input: "::before:active").isFailure)
    #expect(parse(input: ":: before").isFailure)
    #expect(
      parse(input: "div ::after")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .localName(.init(name: "div", lowerName: "div")),
                .combinator(.descendant),
                .combinator(.pseudoElement),
                .pseudoElement(.after),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 2),
              flags: .hasPseudo)
          ]
          )))
    #expect(
      parse(input: "#d1 > .ok")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .id("d1"),
                .combinator(.child),
                .class("ok"),
              ],
              specificity: Specificity(idSelectors: 1, classLikeSelectors: 1, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(!parse(input: ":not(#provel.old)").isFailure)
    #expect(!parse(input: ":not(#provel > old)").isFailure)
    #expect(!parse(input: "table[rules]:not([rules=\"none\"]):not([rules=\"\"])").isFailure)
    parser.defaultNS = nil
    #expect(
      parseNS(input: ":not(*)", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .negation(
                  .init(slice: [
                    .init(
                      slice: [
                        .explicitUniversalType
                      ],
                      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
                      flags: .empty)
                  ]))
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNS(input: ":not(|*)", parser: parser)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .negation(
                  .init(slice: [
                    .init(
                      slice: [
                        .explicitNoNamespace,
                        .explicitUniversalType,
                      ],
                      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
                      flags: .empty)
                  ]))
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(
      parseNSExpected(input: ":not(*|*)", parser: parser, expected: ":not(*)")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .negation(
                  .init(slice: [
                    .init(
                      slice: [
                        .explicitUniversalType
                      ],
                      specificity: .init(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
                      flags: .empty)
                  ]))
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
              flags: .empty)
          ]
          )))
    #expect(!parse(input: "::highlight(foo)").isFailure)

    #expect(parse(input: "::slotted()").isFailure)
    #expect(!parse(input: "::slotted(div)").isFailure)
    #expect(parse(input: "::slotted(div).foo").isFailure)
    #expect(parse(input: "::slotted(div + bar)").isFailure)
    #expect(parse(input: "::slotted(div) + foo").isFailure)

    #expect(parse(input: "::part()").isFailure)
    #expect(parse(input: "::part(42)").isFailure)
    #expect(!parse(input: "::part(foo bar)").isFailure)
    #expect(!parse(input: "::part(foo):hover").isFailure)
    #expect(parse(input: "::part(foo) + bar").isFailure)

    #expect(!parse(input: "div ::slotted(div)").isFailure)
    #expect(!parse(input: "div + slot::slotted(div)").isFailure)
    #expect(!parse(input: "div + slot::slotted(div.foo)").isFailure)
    #expect(parse(input: "slot::slotted(div,foo)::first-line").isFailure)
    #expect(!parse(input: "::slotted(div)::before").isFailure)
    #expect(parse(input: "slot::slotted(div,foo)").isFailure)

    #expect(!parse(input: "foo:where()").isFailure)
    #expect(!parse(input: "foo:where(div, foo, .bar baz)").isFailure)
    #expect(!parse(input: "foo:where(::before)").isFailure)
  }

  @Test("parent selector parsing and replaceParentSelector behavior")
  func parentSelector() throws {
    #expect(!parse(input: "foo &").isFailure)
    #expect(
      parse(input: "#foo &.bar")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .id("foo"),
                .combinator(.descendant),
                .parentSelector,
                .class("bar"),
              ],
              specificity: Specificity(idSelectors: 1, classLikeSelectors: 1, elementSelectors: 0),
              flags: .hasParent)
          ]
          )))
    let parent = try parse(input: ".bar, div .baz").get()
    let child = try parse(input: "#foo &.bar").get()
    let expected1 = try parse(input: "#foo :is(.bar, div .baz).bar").get()
    #expect(child.replaceParentSelector(parent) == expected1)
    let hasChild = try parse(input: "#foo:has(&.bar)").get()
    let expected2 = try parse(input: "#foo:has(:is(.bar, div .baz).bar)").get()
    #expect(hasChild.replaceParentSelector(parent) == expected2)
    do {
      let child = try parseRelativeExpected(input: "#foo", parseRelative: .forNesting, expected: "& #foo").get()
      let expected3 = try parse(input: ":is(.bar, div .baz) #foo").get()
      #expect(child.replaceParentSelector(parent) == expected3)
    }
    let left = try parseRelativeExpected(input: "+ #foo", parseRelative: .forNesting, expected: "& + #foo").get()
    let right = try parse(input: "& + #foo").get()
    #expect(left == right)
  }

  @Test("pseudo iterator yields expected sequence")
  func pseudoIter() throws {
    let list = try parse(input: "q::before").get()
    let selector = list.slice[0]
    #expect(!selector.isUniversal)
    var iter = selector.makeIterator()
    #expect(iter.next() == .pseudoElement(.before))
    #expect(iter.next() == nil)
    let combinator = iter.nextSequence()
    #expect(combinator == .pseudoElement)
    #expect(iter.next() == .localName(.init(name: "q", lowerName: "q")))
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == nil)
  }

  @Test("pseudo before and marker iteration order")
  func pseudoBeforeMarker() throws {
    let list = try parse(input: "::before::marker").get()
    let selector = list.slice[0]
    var iter = selector.makeIterator()
    #expect(iter.next() == .pseudoElement(.marker))
    #expect(iter.next() == nil)
    let combinator = iter.nextSequence()
    #expect(combinator == .pseudoElement)
    #expect(iter.next() == .pseudoElement(.before))
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == .pseudoElement)
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == nil)
  }

  @Test("duplicate before/after/marker are failures")
  func pseudoDuplicateBeforeAfterOrMarker() {
    #expect(parse(input: "::before::before").isFailure)
    #expect(parse(input: "::after::after").isFailure)
    #expect(parse(input: "::marker::marker").isFailure)
  }

  @Test("element-backed pseudo iteration order")
  func pseudoOnElementBackedPseudo() throws {
    let list = try parse(input: "::details-content::before").get()
    let selector = list.slice[0]
    var iter = selector.makeIterator()
    #expect(iter.next() == .pseudoElement(.before))
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == .pseudoElement)
    #expect(iter.next() == .pseudoElement(.detailsContent))
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == .pseudoElement)
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == nil)
  }

  @Test("universal selector detection")
  func universal() throws {
    let list = try parseNS(input: "*|*::before", parser: DummyParser.defaultWithNamespace(defaultNS: "https://example.com")).get()
    let selector = list.slice[0]
    #expect(selector.isUniversal)
  }

  @Test("empty pseudo iterator behavior")
  func emptyPseudoIter() throws {
    let list = try parse(input: "::before").get()
    let selector = list.slice[0]
    #expect(selector.isUniversal)
    var iter = selector.makeIterator()
    #expect(iter.next() == .pseudoElement(.before))
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == .pseudoElement)
    #expect(iter.next() == nil)
    #expect(iter.nextSequence() == nil)
  }

  @Test("implicit scope parsing and :scope behavior")
  func parseImplicitScope() {
    #expect(
      parseRelativeExpected(input: ".foo", parseRelative: .forScope, expected: nil)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .implicitScope,
                .combinator(.descendant),
                .class("foo"),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
              flags: .hasScope)
          ]
          )))
    #expect(
      parseRelativeExpected(input: ":scope .foo", parseRelative: .forScope, expected: nil)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .scope,
                .combinator(.descendant),
                .class("foo"),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 2, elementSelectors: 0),
              flags: .hasScope)
          ]
          )))
    #expect(
      parseRelativeExpected(input: "> .foo", parseRelative: .forScope, expected: "> .foo")
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .implicitScope,
                .combinator(.child),
                .class("foo"),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
              flags: .hasScope)
          ]
          )))
    #expect(
      parseRelativeExpected(input: ".foo :scope > .bar", parseRelative: .forScope, expected: nil)
        == .success(
          SelectorList<DummySelectorImpl>(slice: [
            .init(
              slice: [
                .class("foo"),
                .combinator(.descendant),
                .scope,
                .combinator(.child),
                .class("bar"),
              ],
              specificity: Specificity(idSelectors: 0, classLikeSelectors: 3, elementSelectors: 0),
              flags: .hasScope)
          ]
          )))
  }

  func parse(input: String) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseRelative(input: input, parseRelative: .no)
  }

  func parseRelative(input: String, parseRelative: ParseRelative) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseNSRelative(input: input, parser: DummyParser.default(), parseRelative: parseRelative)
  }

  func parseExpected(input: String, expected: String?) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseNSExpected(input: input, parser: DummyParser.default(), expected: expected)
  }

  func parseRelativeExpected(input: String, parseRelative: ParseRelative, expected: String?) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseNSRelativeExpected(input: input, parser: DummyParser.default(), parseRelative: parseRelative, expected: expected)
  }

  func parseNSRelative(input: String, parser: DummyParser, parseRelative: ParseRelative) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseNSRelativeExpected(input: input, parser: parser, parseRelative: parseRelative, expected: nil)
  }

  func parseNS(input: String, parser: DummyParser) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseNSRelative(input: input, parser: parser, parseRelative: .no)
  }

  func parseNSExpected(
    input: String,
    parser: DummyParser,
    expected: String?,
  ) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    parseNSRelativeExpected(input: input, parser: parser, parseRelative: .no, expected: expected)
  }

  func parseNSRelativeExpected(
    input: String,
    parser: DummyParser,
    parseRelative: ParseRelative,
    expected: String?,
  ) -> Result<SelectorList<DummySelectorImpl>, SelectorParseError> {
    let parserInput = ParserInput(input: input)
    var cssParser = CSSParser(input: parserInput)
    let result: Result<SelectorList<DummySelectorImpl>, ParseError<DummyParser.Failure>> = SelectorList.parse(parser: parser, input: &cssParser, parseRelative: parseRelative)
    if case .success(let selectors) = result {
      #expect(selectors.toCSSString() == (expected ?? input))
    }
    return result
  }
}
