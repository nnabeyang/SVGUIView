import Foundation
import Synchronization

/// The cascaded values of the copies that `<use>` elements show, by the element that they copy.
///
/// SVG 2 puts the copy of an element in a tree of its own, where selectors match without the ancestors and siblings
/// of the element in the document. The copy of an element is the same for every `<use>` element that shows it, so its
/// cascaded values are found once, the first time that a `<use>` element shows it, and kept while the document and
/// its style sheets stay the same.
final class InstanceStyles: Sendable {
  /// The document whose elements are copied, with the attributes that animations set.
  private let document: DocumentTree
  private let stylesheet: Stylesheet
  private let cascades = Mutex<[ElementID: [ElementID: CascadedValues]]>([:])

  init(document: DocumentTree, stylesheet: Stylesheet) {
    self.document = document
    self.stylesheet = stylesheet
  }

  /// The cascaded values of the copy of an element and of its descendants, by their elements, or `nil` if the
  /// element isn't in the document.
  func cascades(ofCopyOf id: ElementID) -> [ElementID: CascadedValues]? {
    if let cascades = cascades.withLock({ $0[id] }) { return cascades }
    guard let element = document.cursor(at: id)?.element else { return nil }
    var found = [ElementID: CascadedValues]()
    func visit(_ cursor: ElementCursor) {
      found[cursor.element.id] = cascade(element: cursor, stylesheet: stylesheet)
      for index in cursor.element.children.indices {
        visit(cursor.child(at: index))
      }
    }
    visit(ElementCursor(instanceRoot: element))
    cascades.withLock { $0[id] = found }
    return found
  }
}
