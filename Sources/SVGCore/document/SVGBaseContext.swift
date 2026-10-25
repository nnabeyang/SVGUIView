import CoreGraphics
import Foundation

/// The `@keyframes` rules of a document, and the time that its animations are at.
struct DocumentAnimations: Sendable {
  /// The rules by their names. Of rules with the same name, the last one in the document wins.
  let keyframes: [String: KeyframesRule]
  /// The time since the document was loaded, in seconds.
  var time: Double
}

package struct SVGBaseContext: Sendable {
  /// The parsed document, which the elements to render are made from.
  let document: SVGDocument
  package let root: SVGSVGElement?
  let animations: DocumentAnimations
  private(set) var pservers = [String: any SVGGradientServer]()
  private(set) var contentIdMap = [String: ObjectIdentifier]()
  private(set) var contents = [ObjectIdentifier: any SVGElement]()

  var clipPaths = [String: SVGClipPathElement]()
  var masks = [String: SVGMaskElement]()
  var patterns = [String: SVGPatternElement]()
  var filters = [String: SVGFilterElement]()

  /// The context of the elements made from a document. Of elements with the same ID, the first one in the document
  /// is the one that references find.
  init(document: SVGDocument, root: SVGSVGElement?, animations: DocumentAnimations) {
    self.document = document
    self.root = root
    self.animations = animations
    guard let root else { return }
    for content in root.elements {
      let identifier = content.index
      contents[identifier] = content
      switch content {
      case let content as any SVGDrawableElement:
        if let id = content.id, contentIdMap[id] == nil {
          contentIdMap[id] = identifier
        }
      case let pserver as any SVGGradientServer:
        if let id = pserver.id, pservers[id] == nil {
          pservers[id] = pserver
        }
      default:
        break
      }
    }
    root.clip(context: &self)
    root.mask(context: &self)
    root.pattern(context: &self)
    root.filter(context: &self)
  }

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
