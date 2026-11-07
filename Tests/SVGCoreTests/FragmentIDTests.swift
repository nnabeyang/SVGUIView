import Foundation
import Testing

@testable import SVGCore

@Suite("References in href")
struct FragmentIDTests {
  @Test(
    "a local reference names the ID with its percent-encoded characters decoded",
    arguments: [
      ("#a", "a"), (" #a ", "a"), ("#a%20b", "a b"), ("#%E3%81%82", "あ"), ("#100%", "100%"), ("#bad%zz", "bad%zz"),
    ])
  func decoded(href: String, id: String) {
    #expect(fragmentID(of: href) == id)
  }

  @Test("an href that isn't a local reference names no ID", arguments: ["", "#", "a", "image.svg#a", "data:,a"])
  func notLocal(href: String) {
    #expect(fragmentID(of: href) == nil)
  }

  @Test("a use element finds the element that an encoded reference names")
  func encodedReferences() throws {
    let svg = #"""
      <svg xmlns="http://www.w3.org/2000/svg">
        <defs>
          <rect id="a b" width="10" height="10"/>
        </defs>
        <use href="#a%20b"/>
      </svg>
      """#
    let base = SVGParser.parse(data: Data(svg.utf8), languages: ["en"])
    let use = try #require(base.root?.children.compactMap { $0 as? SVGUseElement }.first)
    #expect(use.parentId == "a b")
    #expect(base[use.parentId ?? ""] != nil)
  }
}
