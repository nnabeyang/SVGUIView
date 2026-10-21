import CoreGraphics
import Foundation

package struct SVGBaseContext: Sendable {
  /// The parsed document, which the elements to render are made from.
  let document: SVGDocument
  package let root: SVGSVGElement?
  let pservers: [String: any SVGGradientServer]
  let contentIdMap: [String: ObjectIdentifier]
  let contents: [ObjectIdentifier: any SVGElement]

  var clipPaths = [String: SVGClipPathElement]()
  var masks = [String: SVGMaskElement]()
  var patterns = [String: SVGPatternElement]()
  var filters = [String: SVGFilterElement]()

  mutating func setClipPath(id: String, value: SVGClipPathElement) {
    if clipPaths[id] == nil {
      clipPaths[id] = value
    }
  }

  mutating func setMask(id: String, value: SVGMaskElement) {
    if masks[id] == nil {
      masks[id] = value
    }
  }

  mutating func setPattern(id: String, value: SVGPatternElement) {
    if patterns[id] == nil {
      patterns[id] = value
    }
  }

  mutating func setFilter(id: String, value: SVGFilterElement) {
    if filters[id] == nil {
      filters[id] = value
    }
  }

  subscript(id: String) -> (any SVGDrawableElement)? {
    guard let idx = contentIdMap[id],
      let element = contents[idx] as? (any SVGDrawableElement)
    else { return nil }
    return element
  }
}
