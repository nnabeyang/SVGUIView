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
  /// The `color-interpolation-filters` of the primitive, the color space that its inputs are converted to and that
  /// it computes its result in.
  package let colorSpace: SVGColorInterpolation
}

package enum FilterPrimitive: Sendable {
  case blend(mode: CGBlendMode, input: SVGFilterInput?, input2: SVGFilterInput?)
  /// A matrix of 4 rows of 5 numbers, for red, green, blue and alpha, that multiplies the components of each pixel
  /// without its alpha premultiplied, from 0 to 1, followed by 1.
  case colorMatrix(input: SVGFilterInput?, matrix: [Float])
  /// The first input composited over, in, out of, atop or xor the second, or combined with it by the coefficients
  /// `k1` to `k4` of `arithmetic`.
  case composite(operator: SVGCompositeOperator, k: [Float], input: SVGFilterInput?, input2: SVGFilterInput?)
  /// Functions that map each component of each pixel, without its alpha premultiplied, from 0 to 1.
  case componentTransfer(
    input: SVGFilterInput?, red: TransferFunction, green: TransferFunction, blue: TransferFunction,
    alpha: TransferFunction)
  /// A flood with the components of its color, premultiplied, in the order of the pixels of the bitmap.
  case flood(color: [UInt8])
  case gaussianBlur(GaussianBlurPrimitive)
  case merge(inputs: [SVGFilterInput?])
  case offset(translation: CGAffineTransform)
}

/// The transfer function of a component of a `feComponentTransfer`, from its `feFuncR`, `feFuncG`, `feFuncB` or
/// `feFuncA`.
package enum TransferFunction: Sendable, Equatable {
  case identity
  /// Linear interpolation between values at even intervals from 0 to 1.
  case table([Float])
  /// Steps of values of even widths from 0 to 1.
  case discrete([Float])
  case linear(slope: Float, intercept: Float)
  case gamma(amplitude: Float, exponent: Float, offset: Float)

  /// The component that the function maps a component from 0 to 1 to, from 0 to 1.
  package func apply(_ c: Float) -> Float {
    let value: Float
    switch self {
    case .identity:
      return c
    case .table(let values):
      guard let first = values.first else { return c }
      let n = values.count - 1
      guard n > 0 else {
        value = first
        break
      }
      // The interval of the component, where the last one includes 1.
      let k = min(Int(c * Float(n)), n - 1)
      value = values[k] + (c - Float(k) / Float(n)) * Float(n) * (values[k + 1] - values[k])
    case .discrete(let values):
      guard !values.isEmpty else { return c }
      let n = values.count
      value = values[min(Int(c * Float(n)), n - 1)]
    case .linear(let slope, let intercept):
      value = slope * c + intercept
    case .gamma(let amplitude, let exponent, let offset):
      value = amplitude * pow(c, exponent) + offset
    }
    return min(max(value, 0), 1)
  }
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
}
