import UIKit

struct SVGUIStyle: Encodable {
  let decratations: [CSSValueType: CSSDeclaration]
  init(decratations: [CSSValueType: CSSDeclaration]) {
    self.decratations = decratations
  }

  init(description: String) {
    var data = description
    decratations = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var parser = CSSParser(bytes: bytes)
      return parser.parseDeclarations()
    }
  }

  subscript(key: CSSValueType) -> CSSValue? {
    decratations[key]?.value
  }
}
