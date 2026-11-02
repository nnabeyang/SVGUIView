import Foundation

/// The numbers of a list separated by whitespace or a comma with optional whitespace, or `nil` if it has
/// something else.
func numberList(_ text: String) -> [Double]? {
  var numbers = [Double]()
  var expectsNumber = false
  var token = ""
  func flush() -> Bool {
    guard !token.isEmpty else { return true }
    guard let number = Double(token), number.isFinite else { return false }
    numbers.append(number)
    token = ""
    expectsNumber = false
    return true
  }
  for character in text {
    if character == "," {
      // A comma separates two numbers, so it can't follow another comma or start the list.
      guard flush(), !numbers.isEmpty, !expectsNumber else { return nil }
      expectsNumber = true
    } else if character.isWhitespace {
      guard flush() else { return nil }
    } else {
      token.append(character)
    }
  }
  guard flush(), !expectsNumber else { return nil }
  return numbers
}
