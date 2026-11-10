import CoreGraphics
import Foundation

/// The documents in other files that the `<use>` elements of a document show, read and parsed once for a render
/// tree, by the URLs of their files. A file that couldn't be read is `nil`.
final class ExternalDocumentCollector {
  var documents = [URL: SVGBaseContext?]()
}

/// The builder of the document of a `<use>` element that shows an element of another document, which builds what the
/// values that the copy inherits from the `<use>` element reference.
final class OuterBuilder {
  let builder: RenderTreeBuilder

  init(_ builder: RenderTreeBuilder) {
    self.builder = builder
  }
}

/// The references of the values that the copy of an element of another document inherits from the `<use>` element
/// that shows it, which name elements of the document of the `<use>` element, and not of the other document.
///
/// The IDs of those references start with a character that an XML ID can't have, so that the builder of the other
/// document finds them in the document of the `<use>` element. A document in a document in a document marks them
/// again for each document that they cross.
enum OuterReference {
  private static let prefix = "\u{1}"

  /// The ID of an element of the outer document that a reference names, or `nil` if it names one of this document.
  static func outerID(_ id: String) -> String? {
    id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : nil
  }

  /// The computed values of a `<use>` element with the references of its inherited values, the paints and the
  /// markers, marked as references of its document.
  static func marking(_ style: ComputedStyle) -> ComputedStyle {
    var style = style
    func mark(_ paint: Paint) -> Paint {
      if case .url(let id, let fallback) = paint { .url(prefix + id, fallback: fallback) } else { paint }
    }
    func mark(_ marker: SVGMarkerReference) -> SVGMarkerReference {
      if case .url(let id) = marker { .url(prefix + id) } else { marker }
    }
    style.fill = mark(style.fill)
    style.stroke = mark(style.stroke)
    style.markerStart = mark(style.markerStart)
    style.markerMid = mark(style.markerMid)
    style.markerEnd = mark(style.markerEnd)
    return style
  }
}

/// The element that a `<use>` element shows, with what builds its copy.
struct ReferencedElement {
  /// The copy of the element, with its computed values computed again with the `<use>` element as its parent.
  let element: any SVGDrawableElement
  let references: ReferenceGuard
  /// The builder of the document of the element, which is another one than the document of the `<use>` element
  /// where the element is in another file.
  let builder: RenderTreeBuilder
  /// The context of the `<use>` element, whose references find the elements of the document of the element.
  let context: ResolveContext
  /// The IDs that the instance chain of the copy adds after the `<use>` element, which tell the elements of another
  /// document apart from the elements of the document of the `<use>` element that have the same IDs.
  let instance: [ElementID]
}

extension RenderTreeBuilder {
  /// The deepest chain of documents that `<use>` elements show in other files.
  static let maxDocumentDepth = 3

  /// The builder of the document in another file that a `<use>` element shows, or `nil` if the loader doesn't read
  /// the file, it isn't an SVG document, the document is already in the chain of documents that shows it, or the
  /// chain is as deep as is drawn.
  func externalBuilder(for url: String) async -> RenderTreeBuilder? {
    guard let file = resources.fileURL(ofHref: url), !documentChain.contains(file),
      documentChain.count < Self.maxDocumentDepth
    else { return nil }
    let document: SVGBaseContext?
    if let read = documents.documents[file] {
      document = read
    } else {
      let parsed = await resources.data(forHref: url).flatMap { data -> SVGBaseContext? in
        let document = SVGParser.parse(data: data, languages: base.document.languages)
        return document.root == nil ? nil : document
      }
      guard !Task.isCancelled else { return nil }
      documents.documents[file] = .some(parsed)
      document = parsed
    }
    guard let document else { return nil }
    return RenderTreeBuilder(
      external: document, of: self, resources: resources.rebased(to: file), chain: documentChain + [file])
  }

  /// The builder of the document whose element a reference names, and the ID of the element there: this builder,
  /// or the builder of the document of the `<use>` element that a value that the copy inherits came from.
  func owner(ofReference id: String) -> (builder: RenderTreeBuilder, id: String) {
    guard let outerID = OuterReference.outerID(id), let outer else { return (self, id) }
    return outer.builder.owner(ofReference: outerID)
  }

  /// The ID that the instance chain of the copy of an element of another document adds, which no element of a
  /// document has, one for each depth of documents.
  var externalDocumentMarker: ElementID {
    ElementID(rawValue: Int.min / 2 + documentChain.count)
  }
}
