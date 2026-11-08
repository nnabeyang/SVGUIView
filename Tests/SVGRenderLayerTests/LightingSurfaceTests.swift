import Testing
import simd

@testable import SVGRenderCG

/// Tests that the normals of the surface of a lighting primitive inside its edges are the ones that the Sobel kernels
/// with the edges give there.
@Suite("Lighting surface")
struct LightingSurfaceTests {
  @Test("the normals inside the edges are the ones that the kernels with the edges give", arguments: [1, 2.5, -7] as [Float])
  func innerNormals(scale: Float) {
    let width = 9
    let height = 7
    // A surface with irregular heights, from a fixed sequence.
    var generator = FixedSequence(seed: 0x5EED)
    let alpha = (0..<(width * height)).map { _ in Float(generator.next() % 256) / 255 }
    let surface = LightingSurface(alpha: alpha, width: width, height: height, scale: scale)
    for y in 1..<(height - 1) {
      for x in 1..<(width - 1) {
        #expect(surface.innerNormal(x: x, y: y) == surface.edgeNormal(x: x, y: y), "at (\(x), \(y))")
      }
    }
  }
}

/// A generator of a fixed sequence of numbers.
private struct FixedSequence: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    // SplitMix64.
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
