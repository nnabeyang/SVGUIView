import _CSSParser

struct SVGUIInlineStyle {
  let declarations: [CSSDeclaration]

  init(description: String) {
    let parseInput = ParserInput(input: description)
    var input = Parser(input: parseInput)
    declarations = CSSDeclarationParser.declarations(in: &input)
  }
}
