import Accelerate
import Foundation
import SVGCore

extension GaussianBlurPrimitive {
  /// The largest size of a tent that vImage convolves fast. vImage takes about a hundred times as long for larger
  /// ones.
  package static let largestFastTentSize = 127

  /// The largest number of columns that `tentConvolve(_:into:size:)` blurs together, which keeps the rows of sums
  /// that it holds small, however wide the image is.
  private static let tentBandWidth = 2048

  /// Blurs the pixels of `source` into `destination` with a tent of an odd size in both directions, with transparent
  /// black outside the edges, as `vImageTentConvolve_ARGB8888` does with `kvImageBackgroundColorFill`, and with the
  /// same results.
  ///
  /// The weights of a tent of size 2h - 1 are h - |d| at the distance d from the center in each direction, and the
  /// sum of the weighted pixels is divided by h⁴ and rounded once, after both directions. The sums in each direction
  /// are kept up to date from one pixel to the next, so each pixel takes the same time whatever the size of the tent.
  package static func tentConvolve(_ source: vImage_Buffer, into destination: vImage_Buffer, size: Int) {
    let width = Int(source.width)
    for start in stride(from: 0, to: width, by: tentBandWidth) {
      TentBand(
        source: source, destination: destination, h: (size + 1) / 2, start: start,
        columns: min(tentBandWidth, width - start)
      ).convolve()
    }
  }
}

/// The columns of an image that a tent blurs together, with the sums across the rows that the sums down the columns
/// take.
private struct TentBand {
  let source: vImage_Buffer
  let destination: vImage_Buffer
  /// The half size of the tent, whose weight at the center is h.
  let h: Int
  /// The first column of the band.
  let start: Int
  let columns: Int

  /// Blurs the band of the source into the destination.
  func convolve() {
    let height = Int(source.height)
    guard columns > 0, height > 0 else { return }
    // The sums across the rows are needed from h rows above a row to h rows below it, and one more for the next.
    let ringRows = 2 * h + 2
    let ring = UnsafeMutablePointer<SIMD4<Int32>>.allocate(capacity: ringRows * columns)
    defer { ring.deallocate() }
    let zeros = UnsafeMutablePointer<SIMD4<Int32>>.allocate(capacity: columns)
    zeros.initialize(repeating: .zero, count: columns)
    defer { zeros.deallocate() }
    // A row of the source with h + 1 transparent pixels on each side, from the column start - h.
    let lineCount = columns + 2 * h + 1
    let line = UnsafeMutablePointer<SIMD4<Int32>>.allocate(capacity: lineCount)
    line.initialize(repeating: .zero, count: lineCount)
    defer { line.deallocate() }
    func sums(_ y: Int) -> UnsafeMutablePointer<SIMD4<Int32>> {
      y >= 0 && y < height ? ring + (y % ringRows) * columns : zeros
    }
    for y in 0..<min(h + 1, height) {
      sumAcross(row: y, line: line, into: sums(y))
    }
    let tents = UnsafeMutablePointer<SIMD4<Int64>>.allocate(capacity: columns)
    let lefts = UnsafeMutablePointer<SIMD4<Int32>>.allocate(capacity: columns)
    let rights = UnsafeMutablePointer<SIMD4<Int32>>.allocate(capacity: columns)
    defer {
      tents.deallocate()
      lefts.deallocate()
      rights.deallocate()
    }
    // The tent at the first row, and the sums of the h rows that end at it and that start after it. The rows above
    // the first are transparent.
    tents.initialize(repeating: .zero, count: columns)
    lefts.initialize(repeating: .zero, count: columns)
    rights.initialize(repeating: .zero, count: columns)
    for d in 0..<h {
      let row = sums(d)
      let weight = SIMD4<Int64>(repeating: Int64(h - d))
      for column in 0..<columns {
        tents[column] &+= weight &* SIMD4<Int64>(truncatingIfNeeded: row[column])
      }
    }
    for d in 1...h {
      let row = sums(d)
      for column in 0..<columns { rights[column] &+= row[column] }
    }
    let first = sums(0)
    for column in 0..<columns { lefts[column] = first[column] }
    let fourth = Double(h) * Double(h)
    let divisor = SIMD4<Double>(repeating: fourth * fourth)
    for y in 0..<height {
      let output = destination.data.advanced(by: y * destination.rowBytes).advanced(by: start * 4)
        .assumingMemoryBound(to: SIMD4<UInt8>.self)
      for column in 0..<columns {
        // The sums are exact in a Double, and so is a quotient that is a half, which rounds up.
        let value = SIMD4<Double>(tents[column]) / divisor + 0.5
        output[column] = SIMD4(UInt8(value[0]), UInt8(value[1]), UInt8(value[2]), UInt8(value[3]))
      }
      // The row that the next row adds below replaces one that no row needs any more.
      if y + 1 + h < height {
        sumAcross(row: y + 1 + h, line: line, into: sums(y + 1 + h))
      }
      // Moving one row on adds the rows below the center once more, and the ones up to it once less.
      let entering = sums(y + 1)
      let leaving = sums(y + 1 - h)
      let below = sums(y + 1 + h)
      for column in 0..<columns {
        tents[column] &+= SIMD4<Int64>(truncatingIfNeeded: rights[column] &- lefts[column])
        lefts[column] &+= entering[column] &- leaving[column]
        rights[column] &+= below[column] &- entering[column]
      }
    }
  }

  /// Writes the sums of the tent across a row of the band, which aren't rounded.
  private func sumAcross(row y: Int, line: UnsafeMutablePointer<SIMD4<Int32>>, into sums: UnsafeMutablePointer<SIMD4<Int32>>) {
    let width = Int(source.width)
    let pixels = source.data.advanced(by: y * source.rowBytes).assumingMemoryBound(to: SIMD4<UInt8>.self)
    // The pixels of the line from the column start - h, inside the source.
    let first = max(0, start - h)
    let last = min(width, start + columns + h + 1)
    for x in first..<last {
      line[x - start + h] = SIMD4<Int32>(truncatingIfNeeded: pixels[x])
    }
    // The tent at the first column, and the sums of the h pixels that end at it and that start after it, whose
    // center is at h in the line.
    var tent = SIMD4<Int32>.zero
    var left = SIMD4<Int32>.zero
    var right = SIMD4<Int32>.zero
    for d in (1 - h)..<h {
      tent &+= SIMD4(repeating: Int32(h - abs(d))) &* line[h + d]
    }
    for d in (1 - h)...0 { left &+= line[h + d] }
    for d in 1...h { right &+= line[h + d] }
    for column in 0..<columns {
      sums[column] = tent
      // Moving one pixel on adds the pixels after the center once more, and the ones up to it once less.
      tent &+= right &- left
      left &+= line[h + column + 1] &- line[column + 1]
      right &+= line[2 * h + column + 1] &- line[h + column + 1]
    }
  }
}
