import CoreGraphics
import Foundation

/// An element with a filter, built for the bounds of the element.
///
/// The element is painted without its filter into a bitmap of the filter region, the source image, which the
/// primitives of the filter process one after another.
package struct FilteredNode: Sendable {
  package let id: RenderID
  /// The transform of the element, which the result is drawn with.
  package let transform: CGAffineTransform
  /// The bounds of the element.
  package let frame: CGRect
  /// The filter region.
  package let effectRect: CGRect
  /// The color space of the source image.
  package let colorInterpolation: SVGColorInterpolation
  /// The color space that the primitives draw into.
  package let colorInterpolationFilters: SVGColorInterpolation
  /// The opacity of the element, which each primitive draws its result with.
  package let opacity: CGFloat
  package let primitives: [FilterStep]
  /// The element without its filter.
  package let source: RenderNode?
  /// How the result blends with what's behind the element in its isolation group.
  package var blendMode = CGBlendMode.normal
}

/// A primitive of a filter, with what it shares with the others.
package struct FilterStep: Sendable {
  package let primitive: FilterPrimitive
  /// The primitive subregion, which clips the result.
  package let subregion: CGRect
  /// The name of the result, which later primitives take as an input.
  package let result: String?
  /// Whether the primitive is the first child of the filter element.
  package let isFirst: Bool
}

package enum FilterPrimitive: Sendable {
  case blend(mode: CGBlendMode, input: SVGFilterInput?, input2: SVGFilterInput?)
  /// A flood with the components of its color, premultiplied, in the order of the pixels of the bitmap.
  case flood(color: [UInt8])
  case gaussianBlur(GaussianBlurPrimitive)
  case merge(inputs: [SVGFilterInput?], colorInterpolationFilters: SVGColorInterpolation?)
  case offset(translation: CGAffineTransform)
}

package struct GaussianBlurPrimitive: Sendable {
  /// The smallest standard deviation in pixels that is blurred with three box blurs rather than a Gaussian kernel.
  /// Below it, the boxes differ much from a Gaussian blur, and a Gaussian kernel is small enough to be fast.
  package static let boxBlurMinimumDeviation: CGFloat = 7

  package enum StandardDeviation: Sendable {
    case iso(CGFloat)
    case hetero(x: CGFloat, y: CGFloat)
  }

  package let input: SVGFilterInput?
  package let standardDeviation: StandardDeviation
  /// The `color-interpolation-filters` of the primitive.
  package let colorInterpolationFilters: SVGColorInterpolation?
  /// The `color-interpolation-filters` of the filter element.
  package let filterColorInterpolationFilters: SVGColorInterpolation?
}
