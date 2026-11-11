import CoreGraphics

/// How a rendering fits the document into the rectangle that it renders into, as the content mode of a view.
package struct ContentFit: Sendable {
  /// How the document is aligned in the rectangle and scaled to it. `none` stretches the document to the rectangle,
  /// as `scaleToFill`.
  let preserveAspectRatio: PreserveAspectRatio

  package init(preserveAspectRatio: PreserveAspectRatio) {
    self.preserveAspectRatio = preserveAspectRatio
  }

  /// The transform that places a document of a size, which is the width and the height of its root element, in a
  /// rectangle of the given size.
  func transform(size: CGSize, in rect: CGSize) -> CGAffineTransform {
    preserveAspectRatio.getTransform(viewBox: CGRect(origin: .zero, size: size), size: rect)
  }
}
