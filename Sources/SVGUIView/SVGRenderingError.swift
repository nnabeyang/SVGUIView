/// An error that occurs when an ``SVGUIView`` renders its document.
public enum SVGRenderingError: Error, Sendable, Equatable {
  /// The document has no root `svg` element, such as a document in another namespace.
  case missingRootElement
  /// Rendering took longer than ``SVGUIViewConfiguration/timeoutDuration`` and was cancelled.
  case timedOut
  /// The rectangle to render into, which is the view's frame unless one is given, has no width or no height.
  case zeroSizedRect
}
