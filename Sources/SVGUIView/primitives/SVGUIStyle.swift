import UIKit
import _CSSParser

struct SVGUIStyle: Encodable {
  let decratations: [CSSValueType: CSSDeclaration]
  init(decratations: [CSSValueType: CSSDeclaration]) {
    self.decratations = decratations
  }

  init(description: String) {
    let parseInput = ParserInput(input: description)
    var input = _CSSParser.Parser(input: parseInput)
    var parser = CSSParser(input: input)
    let result = parser.parseQualifiedBlock(prelude: [], start: input.state, input: &input)
    switch result {
    case .success(let rule):
      decratations = rule.declarations
    case .failure:
      decratations = [:]
    }
  }

  subscript(key: CSSValueType) -> CSSValue? {
    decratations[key]?.value
  }
}
