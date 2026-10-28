import Testing

@testable import SVGCore

@Suite("The declarations of a style attribute as text")
struct StyleDeclarationsTests {
  @Test(
    "the declarations of a style attribute, written again",
    arguments: [
      ("fill: red", "fill: red"), ("  fill :red ;opacity:0.5;  ", "fill: red; opacity: 0.5"),
      ("FILL: red", "fill: red"), ("fill: red !important", "fill: red !important"),
      ("fill: red ! IMPORTANT", "fill: red !important"),
      // A later declaration of a property replaces an earlier one, which the cascade does too.
      ("fill: red; opacity: 1; fill: lime", "opacity: 1; fill: lime"),
      // Semicolons in strings and functions don't end a declaration.
      (#"font-family: "a;b", serif; fill: url(#a;b)"#, #"font-family: "a;b", serif; fill: url(#a;b)"#),
      ("clip-path: path('M0 0; L1 1')", "clip-path: path('M0 0; L1 1')"),
      // Declarations without a name, a colon or a value, or with something after `!important`, are left out.
      ("fill; opacity: 1", "opacity: 1"), (": red; opacity: 1", "opacity: 1"), ("fill:; opacity: 1", "opacity: 1"),
      ("fill: red !important x; opacity: 1", "opacity: 1"), ("fill: red ! foo", ""), ("", ""),
    ])
  func parse(text: String, expected: String) {
    #expect(StyleDeclarations(text).text == expected)
  }

  @Test("reading, setting and removing a declaration")
  func change() {
    var style = StyleDeclarations("fill: red; opacity: 0.5 !important")
    #expect(style.declaration(named: "Fill") == .init(name: "fill", value: "red", isImportant: false))
    #expect(style.declaration(named: "opacity")?.isImportant == true)
    #expect(style.declaration(named: "stroke") == nil)
    style.set("fill", to: " lime ", isImportant: false)
    #expect(style.text == "fill: lime; opacity: 0.5 !important")
    style.set("stroke", to: "blue", isImportant: true)
    #expect(style.text == "fill: lime; opacity: 0.5 !important; stroke: blue !important")
    style.remove("OPACITY")
    #expect(style.text == "fill: lime; stroke: blue !important")
  }
}
