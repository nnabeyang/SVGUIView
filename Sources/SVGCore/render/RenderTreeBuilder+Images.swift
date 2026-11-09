import CoreGraphics
import Foundation
import ImageIO

/// An image that an `<image>` or `<feImage>` element shows, read and decoded once for a builder.
struct LoadedImage {
  enum Content {
    case bitmap(CGImage)
    /// An SVG image: a document of its own, without animations, at time zero.
    case document(SVGBaseContext)
  }

  let content: Content
  /// The view box that the `<view>` element that the fragment of the `href` names gives an SVG image, or `nil`.
  let viewBox: CGRect?
}

/// The size and the aspect ratio of an image, where it has them, which `auto` sizes resolve to.
struct IntrinsicSize: Equatable {
  var width: CGFloat?
  var height: CGFloat?
  /// The width divided by the height.
  var ratio: CGFloat?

  /// The size that a `width` and a `height` of `auto`, where they're `nil`, resolve to: the CSS default sizing
  /// algorithm, with the default object size of 300 × 150 for an image that has no size and no ratio.
  func resolved(width: CGFloat?, height: CGFloat?) -> CGSize {
    let defaultSize = CGSize(width: 300, height: 150)
    switch (width, height) {
    case (let width?, let height?):
      return CGSize(width: width, height: height)
    case (let width?, nil):
      return CGSize(width: width, height: ratio.map { width / $0 } ?? self.height ?? defaultSize.height)
    case (nil, let height?):
      return CGSize(width: ratio.map { height * $0 } ?? self.width ?? defaultSize.width, height: height)
    case (nil, nil):
      switch (self.width, self.height, ratio) {
      case (let width?, let height?, _):
        return CGSize(width: width, height: height)
      case (let width?, nil, let ratio?):
        return CGSize(width: width, height: width / ratio)
      case (nil, let height?, let ratio?):
        return CGSize(width: height * ratio, height: height)
      case (let width?, nil, nil):
        return CGSize(width: width, height: defaultSize.height)
      case (nil, let height?, nil):
        return CGSize(width: defaultSize.width, height: height)
      case (nil, nil, let ratio?):
        // The largest size of the ratio that the default object size contains.
        let width = min(defaultSize.width, defaultSize.height * ratio)
        return CGSize(width: width, height: width / ratio)
      case (nil, nil, nil):
        return defaultSize
      }
    }
  }
}

/// The images that a builder has read, by the element that shows them, so that sizing and painting an image decode it
/// once.
final class LoadedImageCollector {
  var images = [ObjectIdentifier: LoadedImage?]()
}

extension LoadedImage {
  /// The size and the ratio of the image.
  ///
  /// A bitmap has the size of its pixels. An SVG image has the size of its root's `width` and `height` where they're
  /// absolute lengths, and the ratio of its view box, or of its size where it has no view box.
  var intrinsicSize: IntrinsicSize {
    switch content {
    case .bitmap(let image):
      let width = CGFloat(image.width)
      let height = CGFloat(image.height)
      return IntrinsicSize(width: width, height: height, ratio: height > 0 ? width / height : nil)
    case .document(let document):
      guard let svg = document.root else { return IntrinsicSize() }
      func absolute(_ length: SVGLength?, mode: SVGLengthMode) -> CGFloat? {
        guard let length, !length.dependsOnViewport else { return nil }
        let value = length.value(context: svg, mode: mode)
        return value >= 0 ? value : nil
      }
      let width = absolute(svg.width, mode: .width)
      let height = absolute(svg.height, mode: .height)
      let viewBox = viewBox ?? svg.viewBox?.toCGRect()
      let ratio: CGFloat? =
        if let viewBox, viewBox.width > 0, viewBox.height > 0 {
          viewBox.width / viewBox.height
        } else if let width, let height, width > 0, height > 0 {
          width / height
        } else {
          nil
        }
      return IntrinsicSize(width: width, height: height, ratio: ratio)
    }
  }
}

extension SVGLength {
  /// Whether the length is relative to a viewport or a box that an SVG image only has once it's placed: a
  /// percentage, a viewport unit, or a sum or a math function with one.
  fileprivate var dependsOnViewport: Bool {
    if hasPercent { return true }
    return terms.contains { term in
      switch term {
      case .vw, .vh, .vi, .vb, .vmin, .vmax, .calc: true
      default: false
      }
    }
  }
}

extension RenderTreeBuilder {
  /// The image that an `<image>` element shows, read and decoded once for the builder, or `nil` if it has none, or
  /// its data isn't an image.
  func loadedImage(of element: SVGImageElement) async -> LoadedImage? {
    let key = ObjectIdentifier(element)
    if let loaded = images.images[key] { return loaded }
    let data: Data?
    switch element.source {
    case .data(let embedded): data = embedded
    case .external(let href): data = await resources.data(forHref: href)
    case nil: data = nil
    }
    let loaded = data.flatMap { loadImage(data: $0, fragment: element.fragment) }
    // A reading that was cancelled isn't kept, as the rendering stops anyway.
    if !Task.isCancelled {
      images.images[key] = .some(loaded)
    }
    return loaded
  }

  /// The image of data: a bitmap, or else an SVG image, or `nil` if the data isn't an image, or is an SVG image deeper
  /// in SVG images than the ones that are drawn.
  ///
  /// - Parameter fragment: The fragment of the URL of the image, which names a `<view>` of an SVG image.
  func loadImage(data: Data, fragment: String?) -> LoadedImage? {
    if let image = EmbeddedImage.decodedImage(of: data), image.width > 0, image.height > 0 {
      return LoadedImage(content: .bitmap(image), viewBox: nil)
    }
    guard imageDepth < Self.maxImageDepth, let data = EmbeddedImage.svgData(of: data) else { return nil }
    let document = SVGParser.parse(data: data, languages: base.document.languages)
    guard document.root != nil else { return nil }
    return LoadedImage(content: .document(document), viewBox: fragment.flatMap { Self.viewBox(of: $0, in: document) })
  }

  /// The view box of the `<view>` element of an SVG image that a fragment names, or `nil` if it names none, or the
  /// view has no valid view box.
  private static func viewBox(of fragment: String, in document: SVGBaseContext) -> CGRect? {
    let tree = document.document
    guard let id = tree.element(id: fragment), tree.localName(of: id) == "view",
      let viewBox = SVGSVGElement.parseViewBox(tree.attributes(of: id)?["viewBox"])?.toCGRect(),
      viewBox.width > 0, viewBox.height > 0
    else { return nil }
    return viewBox
  }

  /// The rectangle of an `<image>` element, whose `width` and `height` of `auto` take the size of its image, in a
  /// context styled by the element, or `nil` if it has no area.
  func imageRect(of element: SVGImageElement, context: ResolveContext) async -> CGRect? {
    let x = element.x?.value(context: context, mode: .width) ?? 0
    let y = element.y?.value(context: context, mode: .height) ?? 0
    let width = element.width?.value(context: context, mode: .width)
    let height = element.height?.value(context: context, mode: .height)
    let size: CGSize
    if let width, let height {
      size = CGSize(width: width, height: height)
    } else {
      let intrinsic = await loadedImage(of: element)?.intrinsicSize ?? IntrinsicSize()
      size = intrinsic.resolved(width: width, height: height)
    }
    guard size.width > 0, size.height > 0 else { return nil }
    return CGRect(origin: CGPoint(x: x, y: y), size: size)
  }
}
