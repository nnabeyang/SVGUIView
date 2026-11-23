import Foundation
import Synchronization

/// The SVG images that the renderings of a document have parsed, by their data, so that each is parsed once, and
/// the renderings at other times only apply their animations at those times.
///
/// An SVG image is processed in the secure animated mode of SVG Integration: its SMIL animations, CSS animations
/// and transitions run on the timeline of the document that shows it, while it reads no other files.
package final class SVGImageDocuments: Sendable {
  private struct Key: Hashable {
    let data: Data
    let languages: [String]
  }

  /// A parsed image, and the time in seconds after which its animations don't change it.
  struct Document: Sendable {
    let context: SVGBaseContext
    let animationEnd: Double
  }

  private let documents = Mutex<[Key: Document]>([:])

  package init() {}

  /// The document of the data of an SVG image, parsed once.
  func document(of data: Data, languages: [String]) -> Document {
    let key = Key(data: data, languages: languages)
    if let document = documents.withLock({ $0[key] }) { return document }
    let context = SVGParser.parse(data: data, languages: languages)
    let document = Document(context: context, animationEnd: context.animationEnd())
    documents.withLock { $0[key] = document }
    return document
  }
}

/// The SVG images whose animations change them, which a builder finds while it builds a tree.
final class AnimatedImageCollector {
  /// The elements that show the images: the `<image>` elements, and the elements whose filters draw the images with
  /// `feImage` primitives.
  var hosts = Set<ElementID>()
  /// The latest time in seconds after which the animations of the images don't change them.
  var end: Double = 0
  /// The latest end of the images that the `feImage` primitives of the filter being built draw, or `nil` if they draw
  /// none that animates.
  var filterImagesEnd: Double?

  func record(_ host: ElementID, end: Double) {
    hosts.insert(host)
    self.end = max(self.end, end)
  }
}

/// The SVG images of a render tree whose animations change them.
package struct AnimatedImages: Sendable, Equatable {
  /// The elements that show the images, whose nodes and painting change while the images animate.
  package var hosts = Set<ElementID>()
  /// The elements whose nodes have the nodes of the hosts in them, which are made again with the hosts.
  package var ancestors = Set<ElementID>()
  /// The latest time in seconds after which the images don't change.
  package var end: Double = 0
  /// Whether an image is drawn where a node of the tree doesn't show it, such as in a pattern, a mask or a marker, so
  /// that which nodes change can't be found from the hosts.
  package var requiresFullRepaint = false

  package init() {}

  package var isEmpty: Bool { hosts.isEmpty }
}

extension RenderNode {
  /// The elements of a set that the node or the nodes in it are made for, through groups, viewports, the content
  /// of `<use>` elements and the sources of filters, but not through paints, clip paths, masks and markers, and the
  /// elements of the nodes that have their nodes in them.
  ///
  /// - Returns: Whether the node or a node in it is made for an element of the set.
  @discardableResult
  func elements(
    in ids: Set<ElementID>, into found: inout Set<ElementID>, ancestors: inout Set<ElementID>
  ) -> Bool {
    var contains = ids.contains(id.element)
    if contains {
      found.insert(id.element)
    }
    let children: [RenderNode] =
      switch self {
      case .shape: []
      case .group(let group): group.children
      case .viewport(let viewport): viewport.content?.children ?? []
      case .use(let use): use.instance?.content.map { [$0] } ?? []
      case .filtered(let filtered): filtered.source.map { [$0] } ?? []
      }
    for child in children where child.elements(in: ids, into: &found, ancestors: &ancestors) {
      contains = true
      ancestors.insert(id.element)
    }
    return contains
  }
}
