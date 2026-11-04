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
  /// The opacity of the element, which the result of the filter is drawn with after the clip path and the mask.
  package let opacity: CGFloat
  package let primitives: [FilterStep]
  /// The element without its filter.
  package let source: RenderNode?
  /// How the result blends with what's behind the element in its isolation group.
  package var blendMode = CGBlendMode.normal
  /// The clip path of the element, which clips the result.
  package var clip: ClipPathEffect?
  /// The mask of the element, which masks the result after the clip path.
  package var mask = MaskApplication.none
}

/// A primitive of a filter, with what it shares with the others.
package struct FilterStep: Sendable {
  package let primitive: FilterPrimitive
  /// The primitive subregion, which clips the result. The attributes that the primitive doesn't have come from the
  /// union of the subregions of its inputs, or from the filter region for a primitive without inputs, one with a
  /// standard input and a `feTile`.
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
  /// What a `feImage` draws, or transparent black for `nil`.
  case image(ImagePrimitive?)
  /// The input convolved with a kernel, or transparent black for `nil`, which values in error give.
  case convolveMatrix(input: SVGFilterInput?, ConvolveMatrixPrimitive?)
  /// The light that the surface of the alpha of the input reflects, or transparent black for `nil`, which a missing
  /// light source, a light source that isn't supported yet and values in error give.
  case lighting(input: SVGFilterInput?, LightingPrimitive?)
  /// The input thinned or fattened by radii in the user space: each component is the least or the greatest in the
  /// rectangle of the radii around its pixel. A radius of 0 doesn't change the input in its direction, and a negative
  /// radius or radii that are both 0 leave the input as it is.
  case morphology(input: SVGFilterInput?, operator: SVGMorphologyOperator, radius: CGSize)
  /// The first input with its pixels moved by the components of the second, the map, without their alpha
  /// premultiplied: a pixel takes the one at the scale in the user space times the component minus 0.5, which is
  /// at most half the scale away.
  case displacementMap(
    input: SVGFilterInput?, input2: SVGFilterInput?, scale: CGSize, x: SVGChannelSelector, y: SVGChannelSelector)
  /// Functions that map each component of each pixel, without its alpha premultiplied, from 0 to 1.
  case componentTransfer(
    input: SVGFilterInput?, red: TransferFunction, green: TransferFunction, blue: TransferFunction,
    alpha: TransferFunction)
  /// A flood with the components of its color, premultiplied, in the order of the pixels of the bitmap.
  case flood(color: [UInt8])
  case gaussianBlur(GaussianBlurPrimitive)
  case merge(inputs: [SVGFilterInput?])
  /// The input moved by a translation.
  case offset(input: SVGFilterInput?, translation: CGAffineTransform)
  /// The rectangle `tile` of the input, which is the subregion of the input, repeated in x and y from its origin.
  case tile(input: SVGFilterInput?, tile: CGRect)
  /// The noise of a `feTurbulence`, or transparent black for `nil`, which values in error give.
  case turbulence(TurbulencePrimitive?)
}

/// The kernel of a `feConvolveMatrix` and how it applies, in pixels of the bitmap of the filter.
///
/// The kernel reaches `targetX` columns to the left of a pixel, `columns - targetX - 1` to the right, and as many
/// rows as `targetY` and `rows - targetY - 1` up and down.
package struct ConvolveMatrixPrimitive: Sendable, Equatable {
  /// The primitive that passes its input through, which the specification gives to a kernel that doesn't have
  /// `columns` times `rows` numbers.
  package static let passThrough = ConvolveMatrixPrimitive(
    columns: 1, rows: 1, kernel: [1], divisor: 1, bias: 0, targetX: 0, targetY: 0, edgeMode: .none,
    preserveAlpha: false)

  package let columns: Int
  package let rows: Int
  /// The numbers of the kernel, row by row, as the attribute gives them.
  package let kernel: [Float]
  package let divisor: Float
  package let bias: Float
  package let targetX: Int
  package let targetY: Int
  package let edgeMode: SVGEdgeMode
  package let preserveAlpha: Bool

  package init(
    columns: Int, rows: Int, kernel: [Float], divisor: Float, bias: Float, targetX: Int, targetY: Int,
    edgeMode: SVGEdgeMode, preserveAlpha: Bool
  ) {
    self.columns = columns
    self.rows = rows
    self.kernel = kernel
    self.divisor = divisor
    self.bias = bias
    self.targetX = targetX
    self.targetY = targetY
    self.edgeMode = edgeMode
    self.preserveAlpha = preserveAlpha
  }
}

/// What a `feImage` draws into its subregion.
package enum ImagePrimitive: Sendable {
  /// An image, placed in the subregion.
  case picture(ImagePaint)
  /// An element of the document, in the user space of the element with the filter moved to the origin of the
  /// subregion, as a `<use>` element of the position of the subregion draws it.
  case element(RenderNode, origin: CGPoint)
}

/// The light of a `feDiffuseLighting` or a `feSpecularLighting`, which a surface whose heights are the alpha of the
/// input reflects.
package struct LightingPrimitive: Sendable, Equatable {
  package enum Reflection: Sendable, Equatable {
    /// The diffuse reflection of a constant, which isn't negative.
    case diffuse(constant: Float)
    /// The specular reflection of a constant, which isn't negative, and an exponent.
    case specular(constant: Float, exponent: Float)
  }

  package enum LightSource: Sendable, Equatable {
    /// A light infinitely far away, whose direction is the azimuth clockwise from the x-axis of the user space and
    /// the elevation above its plane, in degrees.
    case distant(azimuth: Float, elevation: Float)
    /// A light at a position in the user space.
    case point(position: SIMD3<Float>)
    /// A light at a position in the user space, which points at another, focused by an exponent and limited to a
    /// cone of an angle in degrees, if any.
    case spot(position: SIMD3<Float>, pointsAt: SIMD3<Float>, specularExponent: Float, limitingConeAngle: Float?)
  }

  package let reflection: Reflection
  /// The height of the surface where the alpha of the input is 1.
  package let surfaceScale: Float
  /// The red, green and blue of `lighting-color` in sRGB, from 0 to 1. Its alpha isn't used.
  package let color: SIMD3<Float>
  package let lightSource: LightSource

  package init(reflection: Reflection, surfaceScale: Float, color: SIMD3<Float>, lightSource: LightSource) {
    self.reflection = reflection
    self.surfaceScale = surfaceScale
    self.color = color
    self.lightSource = lightSource
  }
}

/// The values of a `feTurbulence` that the reference code of the specification takes.
package struct TurbulencePrimitive: Sendable, Equatable {
  package let type: SVGTurbulenceType
  /// The base frequencies in x and y, which aren't negative.
  package let baseFrequency: CGSize
  /// The number of octaves, which isn't negative.
  package let numOctaves: Int
  /// The seed, truncated to an integer.
  package let seed: Int
  /// Whether the noise stitches at the edges of the primitive subregion.
  package let stitchTiles: Bool

  /// The primitive of the values of an element, or `nil` if a base frequency or the number of octaves is negative,
  /// which the specification doesn't support, and which give transparent black.
  init?(type: SVGTurbulenceType, baseFrequency: CGSize, numOctaves: Int, seed: Double, stitchTiles: Bool) {
    guard baseFrequency.width >= 0, baseFrequency.height >= 0, numOctaves >= 0 else { return nil }
    self.type = type
    self.baseFrequency = baseFrequency
    self.numOctaves = numOctaves
    // The seed is truncated towards 0, and the reference code makes the seeds out of its range the nearest one in it.
    self.seed = Int(min(max(seed.rounded(.towardZero), -0x7FFF_FFFF), 0x7FFF_FFFF))
    self.stitchTiles = stitchTiles
  }
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
