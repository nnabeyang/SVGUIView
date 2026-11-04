import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Paints the noise of a `feTurbulence` in the color space of the primitive, and draws it clipped to the subregion
  /// into `cgContext`, or returns `nil` if its bitmap can't be made or the task is cancelled.
  ///
  /// The noise of a pixel is the one at its corner with the least coordinates in the user space, as in resvg, which
  /// the reference code of Filter Effects 1 computes. A primitive with values in error is transparent black.
  func turbulence(
    _ turbulence: TurbulencePrimitive?, colorSpace: SVGColorInterpolation, subregion: CGRect, bitmapRect: CGRect,
    cgContext: CGContext
  ) -> CGImage? {
    let width = cgContext.width
    let height = cgContext.height
    guard
      let graphics = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace.colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue),
      let data = graphics.data
    else { return nil }
    if let turbulence {
      let pixels = data.bindMemory(to: UInt32.self, capacity: graphics.bytesPerRow / 4 * height)
      let rowLength = graphics.bytesPerRow / 4
      let noise = TurbulenceNoise(turbulence, tile: subregion)
      // The pixels that cover the subregion, whose rows go up from the bottom of the bitmap, as the user space does.
      func covering(from minimum: CGFloat, to maximum: CGFloat, count: Int) -> Range<Int> {
        guard !minimum.isNaN, !maximum.isNaN else { return 0..<0 }
        let lower = Int(max(min(minimum * scale, CGFloat(count)), 0).rounded(.down))
        let upper = Int(max(min(maximum * scale, CGFloat(count)), 0).rounded(.up))
        return lower..<max(lower, upper)
      }
      let columns = covering(
        from: subregion.minX - bitmapRect.minX, to: subregion.maxX - bitmapRect.minX, count: width)
      let rows = covering(from: subregion.minY - bitmapRect.minY, to: subregion.maxY - bitmapRect.minY, count: height)
      for row in rows {
        guard !Task.isCancelled else { return nil }
        let y = Double(bitmapRect.minY) + Double(row) / Double(scale)
        let offset = (height - 1 - row) * rowLength
        for column in columns {
          let x = Double(bitmapRect.minX) + Double(column) / Double(scale)
          pixels[offset + column] = Self.pixel(noise.color(at: SIMD2(x, y)))
        }
      }
    }
    guard let image = graphics.makeImage() else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// The pixel of a color whose red, green, blue and alpha are from 0 to 1 without the alpha premultiplied, in the
  /// order of the bitmap, premultiplied first in the byte order of the host.
  private static func pixel(_ color: SIMD4<Double>) -> UInt32 {
    let alpha = color[3]
    func component(_ value: Double) -> UInt32 { UInt32((value * 255).rounded()) }
    return component(alpha) << 24 | component(color[0] * alpha) << 16 | component(color[1] * alpha) << 8
      | component(color[2] * alpha)
  }
}

/// The noise of a `feTurbulence`, from the reference code of Filter Effects 1, with the tables of its seed.
///
/// The four channels, red, green, blue and alpha, are computed together, as they share the lattice and differ only
/// in their gradients.
struct TurbulenceNoise {
  private static let bSize = 0x100
  private static let bm = 0xff
  private static let perlinN = 0x1000
  private static let randM = 2_147_483_647
  private static let randA = 16807
  private static let randQ = 127_773
  private static let randR = 2836
  /// The most octaves that are computed. An octave after them adds less than 2⁻³² of the first, which doesn't change
  /// the pixels.
  private static let maximumOctaves = 32

  /// The lattice and the stitching of the octave where the noise starts.
  private struct StitchInfo {
    var width: Int
    var height: Int
    var wrapX: Int
    var wrapY: Int
  }

  private let fractalSum: Bool
  private let baseFrequency: SIMD2<Double>
  private let numOctaves: Int
  private let stitch: StitchInfo?
  private var latticeSelector: [Int]
  /// The x and the y of the gradients of the four channels.
  private var gradientX: [SIMD4<Double>]
  private var gradientY: [SIMD4<Double>]

  /// The noise of a primitive whose tiles for stitching are `tile`, the primitive subregion.
  init(_ turbulence: TurbulencePrimitive, tile: CGRect) {
    fractalSum = turbulence.type == .fractalNoise
    numOctaves = min(turbulence.numOctaves, Self.maximumOctaves)
    var frequency = SIMD2(Double(turbulence.baseFrequency.width), Double(turbulence.baseFrequency.height))
    if turbulence.stitchTiles {
      // The frequencies are adjusted so that the tiles have whole numbers of lattice cells.
      func adjusted(_ frequency: Double, _ length: Double) -> Double {
        guard frequency != 0 else { return frequency }
        let lower = (length * frequency).rounded(.down) / length
        let higher = (length * frequency).rounded(.up) / length
        return frequency / lower < higher / frequency ? lower : higher
      }
      frequency.x = adjusted(frequency.x, Double(tile.width))
      frequency.y = adjusted(frequency.y, Double(tile.height))
      let width = Self.integer(Double(tile.width) * frequency.x + 0.5)
      let height = Self.integer(Double(tile.height) * frequency.y + 0.5)
      stitch = StitchInfo(
        width: width, height: height,
        wrapX: Self.integer(Double(tile.minX) * frequency.x + Double(Self.perlinN) + Double(width)),
        wrapY: Self.integer(Double(tile.minY) * frequency.y + Double(Self.perlinN) + Double(height)))
    } else {
      stitch = nil
    }
    baseFrequency = frequency

    let count = Self.bSize + Self.bSize + 2
    latticeSelector = [Int](repeating: 0, count: count)
    gradientX = [SIMD4<Double>](repeating: .zero, count: count)
    gradientY = [SIMD4<Double>](repeating: .zero, count: count)
    var seed = Self.setupSeed(turbulence.seed)
    for k in 0..<4 {
      for i in 0..<Self.bSize {
        latticeSelector[i] = i
        var gradient = SIMD2<Double>()
        for j in 0..<2 {
          seed = Self.random(seed)
          gradient[j] = Double(seed % (Self.bSize + Self.bSize) - Self.bSize) / Double(Self.bSize)
        }
        let length = (gradient.x * gradient.x + gradient.y * gradient.y).squareRoot()
        // A gradient of 0, which the reference code divides by its length of 0, stays 0.
        if length > 0 {
          gradient /= length
        }
        gradientX[i][k] = gradient.x
        gradientY[i][k] = gradient.y
      }
    }
    for i in stride(from: Self.bSize - 1, through: 1, by: -1) {
      let k = latticeSelector[i]
      seed = Self.random(seed)
      let j = seed % Self.bSize
      latticeSelector[i] = latticeSelector[j]
      latticeSelector[j] = k
    }
    for i in 0..<(Self.bSize + 2) {
      latticeSelector[Self.bSize + i] = latticeSelector[i]
      gradientX[Self.bSize + i] = gradientX[i]
      gradientY[Self.bSize + i] = gradientY[i]
    }
  }

  /// The red, green, blue and alpha at a point in the user space, from 0 to 1 without the alpha premultiplied.
  func color(at point: SIMD2<Double>) -> SIMD4<Double> {
    var sum = SIMD4<Double>.zero
    var vector = point * baseFrequency
    var ratio = 1.0
    var stitch = stitch
    for _ in 0..<numOctaves {
      let noise = noise2(vector, stitch: stitch)
      sum += (fractalSum ? noise : SIMD4(abs(noise[0]), abs(noise[1]), abs(noise[2]), abs(noise[3]))) / ratio
      vector *= 2
      ratio *= 2
      if var info = stitch {
        info.width &+= info.width
        info.wrapX = 2 &* info.wrapX &- Self.perlinN
        info.height &+= info.height
        info.wrapY = 2 &* info.wrapY &- Self.perlinN
        stitch = info
      }
    }
    let color = fractalSum ? (sum + 1) / 2 : sum
    return SIMD4(
      Self.clamped(color[0]), Self.clamped(color[1]), Self.clamped(color[2]), Self.clamped(color[3]))
  }

  private func noise2(_ vector: SIMD2<Double>, stitch: StitchInfo?) -> SIMD4<Double> {
    let tx = vector.x + Double(Self.perlinN)
    let ty = vector.y + Double(Self.perlinN)
    // The lattice of a point too far for the integers is left out, as the reference code overflows there.
    guard abs(tx) < 0x1p52, abs(ty) < 0x1p52 else { return .zero }
    var bx0 = Int(tx)
    var bx1 = bx0 + 1
    let rx0 = tx - Double(Int(tx))
    let rx1 = rx0 - 1
    var by0 = Int(ty)
    var by1 = by0 + 1
    let ry0 = ty - Double(Int(ty))
    let ry1 = ry0 - 1
    // When stitching, the lattice points wrap at the edges of the tile.
    if let stitch {
      if bx0 >= stitch.wrapX { bx0 &-= stitch.width }
      if bx1 >= stitch.wrapX { bx1 &-= stitch.width }
      if by0 >= stitch.wrapY { by0 &-= stitch.height }
      if by1 >= stitch.wrapY { by1 &-= stitch.height }
    }
    bx0 &= Self.bm
    bx1 &= Self.bm
    by0 &= Self.bm
    by1 &= Self.bm
    let i = latticeSelector[bx0]
    let j = latticeSelector[bx1]
    let b00 = latticeSelector[i + by0]
    let b10 = latticeSelector[j + by0]
    let b01 = latticeSelector[i + by1]
    let b11 = latticeSelector[j + by1]
    let sx = rx0 * rx0 * (3 - 2 * rx0)
    let sy = ry0 * ry0 * (3 - 2 * ry0)
    var u = rx0 * gradientX[b00] + ry0 * gradientY[b00]
    var v = rx1 * gradientX[b10] + ry0 * gradientY[b10]
    let a = u + sx * (v - u)
    u = rx0 * gradientX[b01] + ry1 * gradientY[b01]
    v = rx1 * gradientX[b11] + ry1 * gradientY[b11]
    let b = u + sx * (v - u)
    return a + sy * (b - a)
  }

  private static func setupSeed(_ seed: Int) -> Int {
    var seed = seed
    if seed <= 0 { seed = -(seed % (randM - 1)) + 1 }
    if seed > randM - 1 { seed = randM - 1 }
    return seed
  }

  private static func random(_ seed: Int) -> Int {
    var result = randA * (seed % randQ) - randR * (seed / randQ)
    if result <= 0 { result += randM }
    return result
  }

  /// The integer of a value truncated towards 0, or 0 for a value too large for the lattice or not a number.
  private static func integer(_ value: Double) -> Int {
    abs(value) < 0x1p52 ? Int(value) : 0
  }

  /// A component from 0 to 1, where a component that isn't a number is 0.
  private static func clamped(_ value: Double) -> Double {
    value.isNaN ? 0 : min(max(value, 0), 1)
  }
}
