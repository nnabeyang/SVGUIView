import CoreGraphics
import Foundation

/// The paints that `context-fill` and `context-stroke` use: the fill and the stroke of the context element, which is
/// the element that references the marker that an element is in, or the `<use>` element that shows it, whichever is
/// nearer, as SVG 2 defines it.
///
/// A paint server of the context element paints in the user space and the bounding box of the context element, so
/// that it continues from the shape to its markers, and from one element that a `<use>` element shows to another.
///
/// It's a class that doesn't change, so that the contexts that carry it, which are copied for every element, stay
/// small.
final class ContextPaint {
  /// A paint of the context element, with the transform from its user space to the user space where it's used.
  struct Channel {
    let source: ContextPaintSource
    /// The transform from the user space of the context element to the current user space.
    var fromContext: CGAffineTransform
  }

  let fill: Channel?
  let stroke: Channel?

  /// The paints of an element as a context element, in its user space. A paint of the element that is itself
  /// `context-fill` or `context-stroke` is the paint of its own context element, which continues from there.
  ///
  /// - Parameters:
  ///   - element: The context element.
  ///   - frame: The bounding box of the element, which its paint servers use.
  ///   - context: The context of the element, styled by the element, which has the context paint of the element.
  ///   - builder: The builder of the document of the element.
  init(
    of element: any SVGDrawableElement, frame: CGRect, context: ResolveContext, builder: RenderTreeBuilder
  ) {
    let style = element.style
    func channel(_ value: Paint) -> Channel? {
      switch value {
      case .contextFill: context.contextPaint?.fill
      case .contextStroke: context.contextPaint?.stroke
      // A paint that paints nothing needs no source.
      case .none: nil
      default:
        Channel(
          source: ContextPaintSource(value: value, element: element, frame: frame, context: context, builder: builder),
          fromContext: .identity)
      }
    }
    fill = channel(style.fill)
    stroke = channel(style.stroke)
  }

  private init(fill: Channel?, stroke: Channel?) {
    self.fill = fill
    self.stroke = stroke
  }

  /// The paint that `context-fill` or `context-stroke` uses, or `nil` for another value or a paint of `none`.
  func channel(for value: Paint) -> Channel? {
    switch value {
    case .contextFill: fill
    case .contextStroke: stroke
    default: nil
    }
  }

  /// Whether one of the paints is a paint server, which the bounds of the context element place.
  var hasServer: Bool {
    fill?.source.value.isServer == true || stroke?.source.value.isServer == true
  }

  /// The paints in the user space that a transform establishes in the current one, such as the one of a child.
  func entering(_ transform: CGAffineTransform) -> ContextPaint {
    guard transform != .identity, fill != nil || stroke != nil else { return self }
    let inverse = transform.inverted()
    func moved(_ channel: Channel?) -> Channel? {
      channel.map { Channel(source: $0.source, fromContext: $0.fromContext.concatenating(inverse)) }
    }
    return ContextPaint(fill: moved(fill), stroke: moved(stroke))
  }
}

/// A paint of a context element, with what paints it: the element, its bounding box, its context and its builder.
final class ContextPaintSource {
  /// The paint, which isn't `context-fill` or `context-stroke`, and whose `currentcolor` is resolved where it's used.
  let value: Paint
  let element: any SVGDrawableElement
  /// The bounding box of the element, in its user space.
  let frame: CGRect
  let context: ResolveContext
  let builder: RenderTreeBuilder

  init(
    value: Paint, element: any SVGDrawableElement, frame: CGRect, context: ResolveContext, builder: RenderTreeBuilder
  ) {
    self.value = value
    self.element = element
    self.frame = frame
    self.context = context
    self.builder = builder
  }
}

extension ResolveContext {
  /// The context with its context paint in the user space that a transform establishes, such as the one of a child.
  func entering(_ transform: CGAffineTransform) -> ResolveContext {
    guard let contextPaint else { return self }
    var context = self
    context.contextPaint = contextPaint.entering(transform)
    return context
  }
}
