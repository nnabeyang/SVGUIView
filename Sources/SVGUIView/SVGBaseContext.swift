struct SVGBaseContext {
    let pservers: [String: any SVGGradientServer]
    let contentIdMap: [String: Int]
    let contents: [SVGElement]
    var root: SVGSVGElement? {
        contents.last as? SVGSVGElement
    }

    subscript(id: String) -> (Index: Int, element: any SVGDrawableElement)? {
        guard let idx = contentIdMap[id],
              let element = contents[idx] as? (any SVGDrawableElement) else { return nil }
        return (Index: idx, element: element)
    }
}
