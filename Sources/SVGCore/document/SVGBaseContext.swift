import CoreGraphics
import Foundation

/// The `@keyframes` rules and the SMIL animations of a document, and the time that its animations are at.
struct DocumentAnimations: Sendable {
  /// The rules by their names. Of rules with the same name, the last one in the document wins.
  let keyframes: [String: KeyframesRule]
  /// The SMIL animations in document order.
  var smil: [SMILAnimation] = []
  /// The time since the document was loaded, in seconds.
  var time: Double
  /// The effects of the SMIL animations at the time, by the elements that they change, in the order that they apply
  /// in.
  var smilEffects: [ElementID: [SMILEffect]] = [:]
}

package struct SVGBaseContext: Sendable {
  /// The parsed document, which the elements to render are made from.
  package let document: DocumentTree
  /// The style sheets of the document, which the cascade of the elements uses.
  let stylesheet: Stylesheet
  package let root: SVGSVGElement?
  let animations: DocumentAnimations
  /// Whether the document has SMIL animations, or an element runs an animation with keyframes, so that the computed
  /// values change with the time.
  package let isAnimated: Bool
  /// The elements whose computed values animations can change, or `nil` for a document without animations.
  let restyleScope: RestyleScope?
  private(set) var pservers = [String: any SVGGradientServer]()
  private(set) var contentIdMap = [String: ObjectIdentifier]()
  private(set) var contents = [ObjectIdentifier: any SVGElement]()

  var clipPaths = [String: SVGClipPathElement]()
  var masks = [String: SVGMaskElement]()
  var patterns = [String: SVGPatternElement]()
  var filters = [String: SVGFilterElement]()

  /// The context of the elements made from a document. Of elements with the same ID, the first one in the document
  /// is the one that references find.
  ///
  /// - Parameter restyleScope: The elements whose computed values animations can change, which the context of the
  ///   document at a time keeps from the context that it comes from, or `nil` to find them.
  init(
    document: DocumentTree, stylesheet: Stylesheet, root: SVGSVGElement?, animations: DocumentAnimations,
    restyleScope: RestyleScope? = nil
  ) {
    self.document = document
    self.stylesheet = stylesheet
    self.root = root
    self.animations = animations
    isAnimated =
      !animations.smil.isEmpty
      || !animations.keyframes.isEmpty
        && (root?.elements ?? []).contains { element in
          element.style.animationName.contains {
            if case .keyframes(let name) = $0 { animations.keyframes[name] != nil } else { false }
          }
        }
    self.restyleScope = restyleScope ?? (isAnimated ? root.map { RestyleScope(root: $0, animations: animations) } : nil)
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

  /// The context with the computed values at the given time, or the context itself if they don't change with the
  /// time.
  ///
  /// - Parameter time: The time since the document was loaded, in seconds.
  package func at(time: Double) -> SVGBaseContext {
    guard isAnimated, let root else { return self }
    var animations = animations
    animations.time = time
    animations.smilEffects = SMILEffect.effects(of: animations.smil, at: time)
    let attributes = SMILEffect.attributes(of: animations.smilEffects, in: document)
    let animated: SVGSVGElement?
    if attributes.isEmpty {
      guard let restyleScope else {
        let animated = root.restyled(parent: nil, root: nil, animations: animations) as? SVGSVGElement
        return SVGBaseContext(document: document, stylesheet: stylesheet, root: animated, animations: animations)
      }
      var replacements = [ObjectIdentifier: any SVGElement]()
      animated =
        root.restyled(parent: nil, root: nil, animations: animations, in: restyleScope, replacements: &replacements)
        as? SVGSVGElement
      return SVGBaseContext(updating: self, root: animated, animations: animations, replacements: replacements)
    } else {
      // Animations of attributes that aren't properties change the attributes before the cascade, so the elements
      // are made again from the document with the animated attributes.
      animated =
        document.replacingAttributes(attributes).root.flatMap {
          ElementCursor(root: $0).makeElement(with: stylesheet, animations: animations)
        } as? SVGSVGElement
    }
    return SVGBaseContext(
      document: document, stylesheet: stylesheet, root: animated, animations: animations, restyleScope: restyleScope)
  }

  /// The context of the elements of this context with some of them made again, which keeps the elements that
  /// references find, with the replaced ones replaced, instead of finding them in the whole tree again.
  ///
  /// - Parameter replacements: The elements that are made again, by the identities of the elements that they
  ///   replace.
  private init(
    updating context: SVGBaseContext, root: SVGSVGElement?, animations: DocumentAnimations,
    replacements: [ObjectIdentifier: any SVGElement]
  ) {
    document = context.document
    stylesheet = context.stylesheet
    self.root = root
    self.animations = animations
    isAnimated = context.isAnimated
    restyleScope = context.restyleScope
    func replaced<T>(_ element: T) -> T where T: SVGElement {
      replacements[element.index] as? T ?? element
    }
    contents = context.contents
    for (old, new) in replacements {
      contents[old] = nil
      contents[new.index] = new
    }
    contentIdMap = context.contentIdMap.mapValues { replacements[$0]?.index ?? $0 }
    pservers = context.pservers.mapValues { replacements[$0.index] as? any SVGGradientServer ?? $0 }
    clipPaths = context.clipPaths.mapValues(replaced)
    masks = context.masks.mapValues(replaced)
    patterns = context.patterns.mapValues(replaced)
    filters = context.filters.mapValues(replaced)
  }

  /// The context with the computed values of every element computed again at the given time, which `at(time:)` does
  /// only for the elements that animations can change.
  func restyledFully(at time: Double) -> SVGBaseContext {
    guard isAnimated, let root else { return self }
    var animations = animations
    animations.time = time
    animations.smilEffects = SMILEffect.effects(of: animations.smil, at: time)
    guard SMILEffect.attributes(of: animations.smilEffects, in: document).isEmpty else { return at(time: time) }
    let animated = root.restyled(parent: nil, root: nil, animations: animations) as? SVGSVGElement
    return SVGBaseContext(
      document: document, stylesheet: stylesheet, root: animated, animations: animations, restyleScope: restyleScope)
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
