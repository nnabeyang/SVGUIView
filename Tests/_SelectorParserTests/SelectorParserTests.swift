import Foundation
import XCTest
import _CSSParser

@testable import _SelectorParser

final class SelectorParserTests: XCTestCase {
  func testVisitor() throws {
    do {
      var testVisitor = TestVisitor(seen: [])
      let list = try parse(input: ":not(:hover) ~ label").get()
      let selector = list.slice[0]
      _ = selector.visit(&testVisitor)
      XCTAssertTrue(testVisitor.seen.contains(":hover"))
    }
    do {
      var testVisitor = TestVisitor(seen: [])
      let list = try parse(input: "::before:hover").get()
      let selector = list.slice[0]
      _ = selector.visit(&testVisitor)
      XCTAssertTrue(testVisitor.seen.contains(":hover"))
    }
  }

  private static let nsSVG: DummyAtom = "http://www.w3.org/2000/svg"
  private static let nsMATHML: DummyAtom = "http://www.w3.org/1998/Math/MathML"
  func testEmpty() {
    let parserInput = ParserInput(input: ":empty")
    var input = CSSParser(input: parserInput)
    let list = SelectorList.parse(
      parser: DummyParser.default(),
      input: &input,
      parseRelative: .no)
    guard case .success = list else {
      XCTFail("Expected to parse successfully")
      return
    }
  }

  func testParsing() {
    XCTAssertTrue(parse(input: "").isFailure)
    XCTAssertTrue(parse(input: ":lang(4)").isFailure)
    XCTAssertTrue(parse(input: ":lang(en US)").isFailure)
    XCTAssertEqual(
      parse(input: "EeÉ"),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .localName(.init(name: "EeÉ", lowerName: "eeÉ"))
            ],
            specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
            flags: .empty)
        ]
        )))
    XCTAssertEqual(
      parse(input: "|e"),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .explicitNoNamespace,
              .localName(.init(name: "e", lowerName: "e")),
            ],
            specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
            flags: .empty)
        ])))
    XCTAssertEqual(
      parseExpected(input: "*|e", expected: "e"),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .localName(.init(name: "e", lowerName: "e"))
            ],
            specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 1),
            flags: .empty)
        ]
        )))
    XCTAssertEqual(
      parseNS(input: "*|e", parser: DummyParser.defaultWithNamespace(defaultNS: "https://example.com")),
      .success(
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
    XCTAssertEqual(
      parse(input: "*"),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .explicitUniversalType
            ],
            specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
            flags: .empty)
        ]
        )))
    XCTAssertEqual(
      parse(input: "|*"),
      .success(
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
    XCTAssertEqual(
      parseExpected(input: "*|*", expected: "*"),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .explicitUniversalType
            ],
            specificity: Specificity(idSelectors: 0, classLikeSelectors: 0, elementSelectors: 0),
            flags: .empty)
        ]
        )))
    XCTAssertEqual(
      parseNS(input: "*|*", parser: DummyParser.defaultWithNamespace(defaultNS: "https://example.com")),
      .success(
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
    XCTAssertEqual(
      parse(input: ".foo:lang(en-US)"),
      .success(
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
    XCTAssertEqual(
      parse(input: "#bar"),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .id("bar")
            ],
            specificity: Specificity(idSelectors: 1, classLikeSelectors: 0, elementSelectors: 0),
            flags: .empty)
        ]
        )))
    XCTAssertEqual(
      parse(input: "e.foo#bar"),
      .success(
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
    XCTAssertEqual(
      parse(input: "e.foo #bar"),
      .success(
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
    XCTAssertEqual(
      parseNS(input: "[Foo]", parser: DummyParser.default()),
      .success(
        SelectorList<DummySelectorImpl>(slice: [
          .init(
            slice: [
              .attributeInNoNamespaceExists(localName: "Foo", localNameLower: "foo")
            ],
            specificity: Specificity(idSelectors: 0, classLikeSelectors: 1, elementSelectors: 0),
            flags: .empty)
        ]
        )))
    XCTAssertTrue(parseNS(input: "svg|circle", parser: DummyParser.default()).isFailure)
    var parser = DummyParser.default()
    parser.nsPrefixes["svg"] = Self.nsSVG
    XCTAssertEqual(
      parseNS(input: "svg|circle", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: "svg|*", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: "[Foo]", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: "e", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: "*", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: "*|*", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: ":not(.cl)", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: ":not(*)", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: ":not(e)", parser: parser),
      .success(
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
    XCTAssertEqual(
      parse(input: "[attr|=\"foo\"]"),
      .success(
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
    XCTAssertEqual(
      parse(input: "::before"),
      .success(
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
    XCTAssertEqual(
      parse(input: "::before:hover"),
      .success(
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
    XCTAssertEqual(
      parse(input: "::before:hover:hover"),
      .success(
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
    XCTAssertTrue(parse(input: "::before:hover:lang(foo)").isFailure)
    XCTAssertTrue(parse(input: "::before:hover .foo").isFailure)
    XCTAssertTrue(parse(input: "::before .foo").isFailure)
    XCTAssertTrue(parse(input: "::before ~ bar").isFailure)
    XCTAssertFalse(parse(input: "::before:active").isFailure)
    XCTAssertTrue(parse(input: ":: before").isFailure)
    XCTAssertEqual(
      parse(input: "div ::after"),
      .success(
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
    XCTAssertEqual(
      parse(input: "#d1 > .ok"),
      .success(
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
    XCTAssertFalse(parse(input: ":not(#provel.old)").isFailure)
    XCTAssertFalse(parse(input: ":not(#provel > old)").isFailure)
    XCTAssertFalse(parse(input: "table[rules]:not([rules=\"none\"]):not([rules=\"\"])").isFailure)
    parser.defaultNS = nil
    XCTAssertEqual(
      parseNS(input: ":not(*)", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNS(input: ":not(|*)", parser: parser),
      .success(
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
    XCTAssertEqual(
      parseNSExpected(input: ":not(*|*)", parser: parser, expected: ":not(*)"),
      .success(
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
    XCTAssertFalse(parse(input: "::highlight(foo)").isFailure)

    XCTAssertTrue(parse(input: "::slotted()").isFailure)
    XCTAssertFalse(parse(input: "::slotted(div)").isFailure)
    XCTAssertTrue(parse(input: "::slotted(div).foo").isFailure)
    XCTAssertTrue(parse(input: "::slotted(div + bar)").isFailure)
    XCTAssertTrue(parse(input: "::slotted(div) + foo").isFailure)

    XCTAssertTrue(parse(input: "::part()").isFailure)
    XCTAssertTrue(parse(input: "::part(42)").isFailure)
    XCTAssertFalse(parse(input: "::part(foo bar)").isFailure)
    XCTAssertFalse(parse(input: "::part(foo):hover").isFailure)
    XCTAssertTrue(parse(input: "::part(foo) + bar").isFailure)

    XCTAssertFalse(parse(input: "div ::slotted(div)").isFailure)
    XCTAssertFalse(parse(input: "div + slot::slotted(div)").isFailure)
    XCTAssertFalse(parse(input: "div + slot::slotted(div.foo)").isFailure)
    XCTAssertTrue(parse(input: "slot::slotted(div,foo)::first-line").isFailure)
    XCTAssertFalse(parse(input: "::slotted(div)::before").isFailure)
    XCTAssertTrue(parse(input: "slot::slotted(div,foo)").isFailure)

    XCTAssertFalse(parse(input: "foo:where()").isFailure)
    XCTAssertFalse(parse(input: "foo:where(div, foo, .bar baz)").isFailure)
    XCTAssertFalse(parse(input: "foo:where(::before)").isFailure)
  }

  func testParentSelector() throws {
    XCTAssertFalse(parse(input: "foo &").isFailure)
    XCTAssertEqual(
      parse(input: "#foo &.bar"),
      .success(
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
    XCTAssertEqual(child.replaceParentSelector(parent), try parse(input: "#foo :is(.bar, div .baz).bar").get())
    let hasChild = try parse(input: "#foo:has(&.bar)").get()
    XCTAssertEqual(
      hasChild.replaceParentSelector(parent),
      try parse(input: "#foo:has(:is(.bar, div .baz).bar)").get())
    do {
      let child = try parseRelativeExpected(input: "#foo", parseRelative: .forNesting, expected: "& #foo").get()
      XCTAssertEqual(
        child.replaceParentSelector(parent),
        try parse(input: ":is(.bar, div .baz) #foo").get())
    }
    XCTAssertEqual(
      try parseRelativeExpected(input: "+ #foo", parseRelative: .forNesting, expected: "& + #foo").get(),
      try parse(input: "& + #foo").get())
  }

  func testPseudoIter() throws {
    let list = try parse(input: "q::before").get()
    let selector = list.slice[0]
    XCTAssertFalse(selector.isUniversal)
    var iter = selector.makeIterator()
    XCTAssertEqual(iter.next(), .pseudoElement(.before))
    XCTAssertNil(iter.next())
    let combinator = iter.nextSequence()
    XCTAssertEqual(combinator, .pseudoElement)
    XCTAssertEqual(iter.next(), .localName(.init(name: "q", lowerName: "q")))
    XCTAssertNil(iter.next())
    XCTAssertNil(iter.nextSequence())
  }

  func testPseudoBeforeMarker() throws {
    let list = try parse(input: "::before::marker").get()
    let selector = list.slice[0]
    var iter = selector.makeIterator()
    XCTAssertEqual(iter.next(), .pseudoElement(.marker))
    XCTAssertNil(iter.next())
    let combinator = iter.nextSequence()
    XCTAssertEqual(combinator, .pseudoElement)
    XCTAssertEqual(iter.next(), .pseudoElement(.before))
    XCTAssertNil(iter.next())
    XCTAssertEqual(iter.nextSequence(), .pseudoElement)
    XCTAssertNil(iter.next())
    XCTAssertNil(iter.nextSequence())
  }

  func testPseudoDuplicateBeforeAfterOrMarker() {
    XCTAssertTrue(parse(input: "::before::before").isFailure)
    XCTAssertTrue(parse(input: "::after::after").isFailure)
    XCTAssertTrue(parse(input: "::marker::marker").isFailure)
  }

  func testPseudoOnElementBackedPseudo() throws {
    let list = try parse(input: "::details-content::before").get()
    let selector = list.slice[0]
    var iter = selector.makeIterator()
    XCTAssertEqual(iter.next(), .pseudoElement(.before))
    XCTAssertNil(iter.next())
    XCTAssertEqual(iter.nextSequence(), .pseudoElement)
    XCTAssertEqual(iter.next(), .pseudoElement(.detailsContent))
    XCTAssertNil(iter.next())
    XCTAssertEqual(iter.nextSequence(), .pseudoElement)
    XCTAssertNil(iter.next())
    XCTAssertNil(iter.nextSequence())
  }

  func testUniversal() throws {
    let list = try parseNS(input: "*|*::before", parser: DummyParser.defaultWithNamespace(defaultNS: "https://example.com")).get()
    let selector = list.slice[0]
    XCTAssertTrue(selector.isUniversal)
  }

  func testEmptyPseudoIter() throws {
    let list = try parse(input: "::before").get()
    let selector = list.slice[0]
    XCTAssertTrue(selector.isUniversal)
    var iter = selector.makeIterator()
    XCTAssertEqual(iter.next(), .pseudoElement(.before))
    XCTAssertNil(iter.next())
    XCTAssertEqual(iter.nextSequence(), .pseudoElement)
    XCTAssertNil(iter.next())
    XCTAssertNil(iter.nextSequence())
  }

  func testParseImplicitScope() throws {
    XCTAssertEqual(
      parseRelativeExpected(input: ".foo", parseRelative: .forScope, expected: nil),
      .success(
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
    XCTAssertEqual(
      parseRelativeExpected(input: ":scope .foo", parseRelative: .forScope, expected: nil),
      .success(
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
    XCTAssertEqual(
      parseRelativeExpected(input: "> .foo", parseRelative: .forScope, expected: "> .foo"),
      .success(
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
    XCTAssertEqual(
      parseRelativeExpected(input: ".foo :scope > .bar", parseRelative: .forScope, expected: nil),
      .success(
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
      XCTAssertEqual(selectors.toCSSString(), expected ?? input)
    }
    return result
  }
}
