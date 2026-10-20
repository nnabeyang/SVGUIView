import CoreGraphics

/// How a rendering fits the document into the rectangle that it renders into, as the content mode of a view.
struct ContentFit: Sendable {
  /// How the view box is aligned in the rectangle and scaled to it.
  let preserveAspectRatio: PreserveAspectRatio
  /// Whether the document is stretched to fill the rectangle, as `scaleToFill`.
  let stretches: Bool
  /// Whether the document is scaled with the rectangle, as the content modes whose names start with `scale`.
  let scales: Bool

  /// The transform that places the view box in a rectangle of the given size.
  func transform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
    preserveAspectRatio.getTransform(viewBox: viewBox, size: size).translatedBy(x: viewBox.minX, y: viewBox.minY)
  }
}
