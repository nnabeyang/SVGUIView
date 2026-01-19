import _CSSParser

struct SVGUIInlineStyle {
  let declarations: [CSSDeclaration]

  init(description: String) {
    let parseInput = ParserInput(input: description)
    var input = Parser(input: parseInput)
    var parser = CSSParser(input: input)
    let result = parser.parseQualifiedBlock(prelude: .init(slice: []), start: input.state, input: &input)
    switch result {
    case .success(let rule):
      declarations = rule.declarations
    case .failure:
      declarations = []
    }
  }
}
