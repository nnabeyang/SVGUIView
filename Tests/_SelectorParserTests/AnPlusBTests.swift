import Foundation
import XCTest

@testable import _SelectorParser

final class AnPlusBTests: XCTestCase {
  func test() {
    XCTAssertEqual(AnPlusB(a: 0, b: 0).toCSSString(), "0")
    XCTAssertEqual(AnPlusB(a: 1, b: 0).toCSSString(), "n")
    XCTAssertEqual(AnPlusB(a: -1, b: 0).toCSSString(), "-n")
    XCTAssertEqual(AnPlusB(a: 24, b: 0).toCSSString(), "24n")
    XCTAssertEqual(AnPlusB(a: -24, b: 0).toCSSString(), "-24n")
    XCTAssertEqual(AnPlusB(a: 0, b: 32).toCSSString(), "32")
    XCTAssertEqual(AnPlusB(a: 0, b: -32).toCSSString(), "-32")
    XCTAssertEqual(AnPlusB(a: 1, b: 32).toCSSString(), "n+32")
    XCTAssertEqual(AnPlusB(a: -1, b: 32).toCSSString(), "-n+32")
    XCTAssertEqual(AnPlusB(a: 24, b: 32).toCSSString(), "24n+32")
  }
}
