import Foundation
import XCTest

@testable import _SelectorParser

final class CaseSensitiveTests: XCTestCase {
  func testIsEqualAsciiCaseInsensitive() {
    XCTAssertTrue(Data("hello".utf8).isEqualAsciiCaseInsensitive(to: Data("HELLO".utf8)))
    XCTAssertFalse(Data("hello".utf8).isEqualAsciiCaseInsensitive(to: Data("HELLA".utf8)))
  }

  func testCaseSensitivityEquals() {
    XCTAssertFalse(CaseSensitivity.caseSensitive.equals(Data("hello".utf8), Data("HELLO".utf8)))
    XCTAssertTrue(CaseSensitivity.asciiCaseInsensitive.equals(Data("hello".utf8), Data("HELLO".utf8)))
  }
}
