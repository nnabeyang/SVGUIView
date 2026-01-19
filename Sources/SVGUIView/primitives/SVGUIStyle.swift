import UIKit
import _CSSParser

struct SVGUIStyle {
  let decratations: [CSSValueType: CSSDeclaration]
  init(decratations: [CSSValueType: CSSDeclaration]) {
    self.decratations = decratations
  }

  subscript(key: CSSValueType) -> CSSValue? {
    decratations[key]?.value
  }
}
