import Foundation
import Testing

@testable import _SelectorParser

@Suite("AnPlusB")
struct AnPlusBTests {
  @Test("toCSSString renders a/an+b forms correctly")
  func toCSSString_RendersCorrectly() {
    #expect(AnPlusB(a: 0, b: 0).toCSSString() == "0")
    #expect(AnPlusB(a: 1, b: 0).toCSSString() == "n")
    #expect(AnPlusB(a: -1, b: 0).toCSSString() == "-n")
    #expect(AnPlusB(a: 24, b: 0).toCSSString() == "24n")
    #expect(AnPlusB(a: -24, b: 0).toCSSString() == "-24n")
    #expect(AnPlusB(a: 0, b: 32).toCSSString() == "32")
    #expect(AnPlusB(a: 0, b: -32).toCSSString() == "-32")
    #expect(AnPlusB(a: 1, b: 32).toCSSString() == "n+32")
    #expect(AnPlusB(a: -1, b: 32).toCSSString() == "-n+32")
    #expect(AnPlusB(a: 24, b: 32).toCSSString() == "24n+32")
  }
}
