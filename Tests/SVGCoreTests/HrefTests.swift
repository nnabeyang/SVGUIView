import Foundation
import Testing

@testable import SVGCore

/// Tests of `href` and the `href` of the XLink namespace, which are separate attributes in SVG 2.
@Suite("href")
struct HrefTests {
  /// The element of a document with an ID, of any kind.
  private func element<E>(_ id: String, in base: SVGBaseContext, as _: E.Type) throws -> E {
    try #require(base.root?.elements.first { $0.base.id == id } as? E, "No \(E.self) has the ID \(id)")
  }

  /// A document whose elements have both `href` and `xlink:href`, and whose element with the ID `x` only has
  /// `xlink:href`.
  private static let svg = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:link="http://www.w3.org/1999/xlink">
      <rect id="a"/><rect id="b"/>
      <linearGradient id="g" href="#a" link:href="#b"/>
      <use id="u" href="#a" link:href="#b"/>
      <image id="i" href="a.png" link:href="b.png"/>
      <image id="x" link:href="b.png"/>
      <image id="e" href="" link:href="b.png"/>
      <text><textPath id="t" href="#a" link:href="#b">t</textPath></text>
      <filter id="f"><feImage id="fi" href="a.png" link:href="b.png"/></filter>
    </svg>
    """##

  @Test("an element that has both uses href, and xlink:href whatever its prefix is where it has no href")
  func hrefWins() throws {
    let base = SVGParser.parse(data: Data(Self.svg.utf8))
    #expect(try element("g", in: base, as: SVGLinearGradientServer.self).parentId == "a")
    #expect(try element("u", in: base, as: SVGUseElement.self).parentId == "a")
    #expect(try element("i", in: base, as: SVGImageElement.self).source == .external("a.png"))
    #expect(try element("x", in: base, as: SVGImageElement.self).source == .external("b.png"))
    // An empty href is still the href, which references nothing.
    #expect(try element("e", in: base, as: SVGImageElement.self).source == nil)
    #expect(try element("t", in: base, as: SVGTSpanElement.self).pathID == "a")
    let feImage = try element("fi", in: base, as: SVGFeImageElement.self)
    guard case .external("a.png") = feImage.source else {
      Issue.record("The feImage doesn't use href: \(String(describing: feImage.source))")
      return
    }
  }

  @Test("the document keeps both attributes, and removing href makes the element use xlink:href")
  func removingHref() throws {
    let base = SVGParser.parse(data: Data(Self.svg.utf8))
    let image = try #require(base.document.element(id: "i"))
    let use = try #require(base.document.element(id: "u"))
    #expect(base.document.attributes(of: image)?["href"] == "a.png")
    #expect(base.document.attributes(of: image)?["xlink:href"] == "b.png")
    let changed = base.changingAttributes([image: ["href": nil], use: ["href": nil]])
    #expect(try element("i", in: changed, as: SVGImageElement.self).source == .external("b.png"))
    #expect(try element("u", in: changed, as: SVGUseElement.self).parentId == "b")
    let removed = changed.changingAttributes([image: ["xlink:href": nil]])
    #expect(try element("i", in: removed, as: SVGImageElement.self).source == nil)
  }

  @Test("a SMIL animation of xlink:href changes xlink:href, which href wins over")
  func animations() throws {
    let svg = ##"""
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
        <rect id="a"/><rect id="b"/><rect id="c"/>
        <use id="u" xlink:href="#a"><set attributeName="xlink:href" to="#c"/></use>
        <use id="v" href="#a" xlink:href="#b"><set attributeName="xlink:href" to="#c"/></use>
        <use id="w" href="#a" xlink:href="#b"><set attributeName="href" to="#c"/></use>
      </svg>
      """##
    let base = SVGParser.parse(data: Data(svg.utf8)).at(time: 0)
    #expect(try element("u", in: base, as: SVGUseElement.self).parentId == "c")
    #expect(try element("v", in: base, as: SVGUseElement.self).parentId == "a")
    #expect(try element("w", in: base, as: SVGUseElement.self).parentId == "c")
  }
}
