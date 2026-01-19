import _SelectorParser

func cascade(_ declarations: [CSSDeclaration]) -> SVGUIStyle {
  var byProperty = [CSSValueType: [CSSDeclaration]]()
  for declaration in declarations {
    if var values = byProperty[declaration.type] {
      values.append(declaration)
      byProperty[declaration.type] = values
    } else {
      byProperty[declaration.type] = [declaration]
    }
  }
  var cascadedValues = [CSSValueType: CSSDeclaration]()
  for (type, declarations) in byProperty {
    guard let declaration = findWinningDeclaration(declarations) else { continue }
    cascadedValues[type] = declaration
  }
  return SVGUIStyle(decratations: cascadedValues)
}

func findWinningDeclaration(_ declarations: [CSSDeclaration]) -> CSSDeclaration? {
  guard !declarations.isEmpty else { return nil }
  var winner = declarations[0]
  for declaration in declarations {
    if declaration > winner {
      winner = declaration
    }
  }
  return winner
}

struct RuleMatch {
  let specificity: Specificity
  let declarations: [CSSDeclaration]
  let sourceOrder: Int
}

func collectDeclarations(matches: [RuleMatch], inlineStyle declarations: [CSSDeclaration]) -> [CSSDeclaration] {
  var allDeclarations: [CSSDeclaration] = []
  for match in matches {
    allDeclarations.append(contentsOf: match.declarations)
  }
  for declaration in declarations {
    allDeclarations.append(
      CSSDeclaration(
        type: declaration.type,
        value: declaration.value,
        importance: declaration.importance,
        specificity: .max,
        sourceOrder: declaration.sourceOrder))
  }
  return allDeclarations
}

func cascadeElement(element: some SVGDrawableElement, stylesheets: [Stylesheet], inlineStyle declarations: [CSSDeclaration]) -> SVGUIStyle {
  var allMatches = [RuleMatch]()
  for stylesheet in stylesheets {
    allMatches.append(contentsOf: stylesheet.matchElement(element: element))
  }
  let declarations = collectDeclarations(matches: allMatches, inlineStyle: declarations)
  return cascade(declarations)
}
