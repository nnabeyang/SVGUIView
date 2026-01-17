import Foundation
import Testing

@testable import _SelectorParser

@Suite("Case sensitivity")
struct CaseSensitiveTests {
  @Test("ASCII case-insensitive equality on Data")
  func isEqualAsciiCaseInsensitive() {
    #expect(Data("hello".utf8).isEqualAsciiCaseInsensitive(to: Data("HELLO".utf8)))
    #expect(!Data("hello".utf8).isEqualAsciiCaseInsensitive(to: Data("HELLA".utf8)))
  }

  @Test("CaseSensitivity.equals behavior")
  func caseSensitivityEquals() {
    #expect(!CaseSensitivity.caseSensitive.equals(Data("hello".utf8), Data("HELLO".utf8)))
    #expect(CaseSensitivity.asciiCaseInsensitive.equals(Data("hello".utf8), Data("HELLO".utf8)))
  }
}
