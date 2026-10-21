import Accelerate
import CoreGraphics
import Foundation
import SVGCore

/// Points `destBuffer` at the input of a primitive.
///
/// `destBuffer` shares its memory with `srcBuffer` or `inputBuffer`, except for the result of another primitive,
/// for which the function allocates the memory.
///
/// - Returns: The memory that the function allocates, if any. The caller frees it after it no longer uses
///   `destBuffer`, or an image that it makes from `destBuffer` without copying the pixels.
func inputImageBuffer(
  input: SVGFilterInput?, format: inout vImage_CGImageFormat, results: [String: CGImage],
  srcBuffer: inout vImage_Buffer, inputBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer
) -> UnsafeMutableRawPointer? {
  switch input {
  case .none:
    destBuffer = inputBuffer
  case .sourceGraphic:
    destBuffer = srcBuffer
  case .sourceAlpha:
    destBuffer = srcBuffer
    dropRGBColor(srcBuffer: &srcBuffer, destBuffer: &destBuffer)
  case .other(let srcName):
    if let image = results[srcName],
      let tbuffer = try? vImage_Buffer(cgImage: image, format: format)
    {
      destBuffer = tbuffer
      return tbuffer.data
    } else {
      destBuffer = inputBuffer
    }
  }
  return nil
}

private func dropRGBColor(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer) {
  let matrix: [Int16] = [
    0, 0, 0, 0,
    0, 0, 0, 0,
    0, 0, 0, 0,
    0, 0, 0, 1,
  ]

  vImageMatrixMultiply_ARGB8888(
    &srcBuffer,
    &destBuffer,
    matrix,
    1,
    nil,
    nil,
    vImage_Flags(kvImageNoFlags)
  )
  swap(&srcBuffer, &destBuffer)
}

/// The input of a primitive, as an image with its own copy of the pixels.
func inputImage(
  input: SVGFilterInput?, format: inout vImage_CGImageFormat, results: [String: CGImage],
  srcBuffer: inout vImage_Buffer, inputBuffer: inout vImage_Buffer
) -> CGImage? {
  guard let data = malloc(inputBuffer.rowBytes * Int(inputBuffer.height)) else { return nil }
  defer {
    free(data)
  }
  var destBuffer = vImage_Buffer(data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
  let resultData = inputImageBuffer(input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer, destBuffer: &destBuffer)
  defer { free(resultData) }

  // Copy the pixels, because the caller draws the image after the buffers are freed.
  return vImageCreateCGImageFromBuffer(
    &destBuffer,
    &format,
    nil,
    nil,
    vImage_Flags(kvImageNoFlags),
    nil)?.takeRetainedValue()
}
