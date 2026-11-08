import _SelectorParser

/// The declarations sorted by precedence in the cascade, from lowest to highest. Of equal declarations, the later
/// one has the higher precedence.
func sortedByPrecedence(_ declarations: [CSSDeclaration]) -> [CSSDeclaration] {
  declarations.enumerated()
    .sorted { $0.element == $1.element ? $0.offset < $1.offset : $0.element < $1.element }
    .map(\.element)
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
        declaration: declaration.declaration,
        importance: declaration.importance,
        specificity: .max,
        sourceOrder: declaration.sourceOrder))
  }
  return allDeclarations
}

/// The cascaded values of an element: the user agent's style sheet, its presentation attributes, then the rules of
/// the style sheet that match it, then its `style` attribute, each overriding the ones before, and important
/// declarations overriding the others.
func cascade(element: ElementCursor, stylesheet: Stylesheet) -> CascadedValues {
  let attributes = element.element.attributes
  // SMIL animations don't change the declarations of `style`, as browsers don't animate it.
  let inlineStyle = element.element.writtenAttributes["style"].map { SVGUIInlineStyle(description: $0).declarations } ?? []
  let declarations = sortedByPrecedence(
    collectDeclarations(matches: stylesheet.matchElement(element: element), inlineStyle: inlineStyle))
  // Important declarations come after the normal ones, so a property with an important declaration has an
  // important one that wins.
  let important = Set(declarations.filter { $0.importance == .important }.compactMap(\.declaration.id))
  return CascadedValues(
    CascadedValues.userAgentDeclarations(of: element.element.name, isRoot: element.isRoot)
      + CascadedValues.presentationAttributes(of: element.element.name, attributes: attributes)
      + declarations.map { declaration in
        var property = declaration.declaration
        if property.id == nil { property.isImportant = declaration.importance == .important }
        return property
      }, important: important)
}
