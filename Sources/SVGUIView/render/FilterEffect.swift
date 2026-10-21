import CoreGraphics
import Foundation

/// An element with a filter, built for the bounds of the element.
///
/// The element is painted without its filter into a bitmap of the filter region, the source image, which the
/// primitives of the filter process one after another.
struct FilteredNode: Sendable {
  let id: RenderID
  /// The transform of the element, which the result is drawn with.
  let transform: CGAffineTransform
  /// The bounds of the element.
  let frame: CGRect
  /// The filter region.
  let effectRect: CGRect
  /// The color space of the source image.
  let colorInterpolation: SVGColorInterpolation
  /// The color space that the primitives draw into.
  let colorInterpolationFilters: SVGColorInterpolation
  /// The opacity of the element, which each primitive draws its result with.
  let opacity: CGFloat
  let primitives: [FilterStep]
  /// The element without its filter.
  let source: RenderNode?
}

/// A primitive of a filter, with what it shares with the others.
struct FilterStep: Sendable {
  let primitive: FilterPrimitive
  /// The primitive subregion, which clips the result.
  let subregion: CGRect
  /// The name of the result, which later primitives take as an input.
  let result: String?
  /// Whether the primitive is the first child of the filter element.
  let isFirst: Bool
}

enum FilterPrimitive: Sendable {
  case blend(mode: CGBlendMode, input: SVGFilterInput?, input2: SVGFilterInput?)
  /// A flood with the components of its color, premultiplied, in the order of the pixels of the bitmap.
  case flood(color: [UInt8])
  case gaussianBlur(GaussianBlurPrimitive)
  case merge(inputs: [SVGFilterInput?], colorInterpolationFilters: SVGColorInterpolation?)
  case offset(translation: CGAffineTransform)
}

struct GaussianBlurPrimitive: Sendable {
  enum StandardDeviation: Sendable {
    case iso(CGFloat)
    case hetero(x: CGFloat, y: CGFloat)
  }

  let input: SVGFilterInput?
  let standardDeviation: StandardDeviation
  /// The `color-interpolation-filters` of the primitive.
  let colorInterpolationFilters: SVGColorInterpolation?
  /// The `color-interpolation-filters` of the filter element.
  let filterColorInterpolationFilters: SVGColorInterpolation?
}
