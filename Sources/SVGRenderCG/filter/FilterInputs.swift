import Accelerate
import CoreGraphics
import Foundation
import SVGCore

/// The input of a primitive converted to the format, in memory of its own, which the caller frees, or `nil` if it
/// can't be converted.
///
/// Only the image of the input is converted: the result of the primitive before for no input or a name that no
/// primitive has given, the source for `SourceGraphic` and `SourceAlpha`, and the named result for a name.
/// `SourceAlpha` keeps the alpha of the source, the fourth component of the pixels, with the colors of 0.
func inputBuffer(
  _ input: SVGFilterInput?, format: vImage_CGImageFormat, srcImage: CGImage, inImage: CGImage,
  results: [String: CGImage]
) -> vImage_Buffer? {
  let image: CGImage =
    switch input {
    case .none: inImage
    case .sourceGraphic, .sourceAlpha: srcImage
    case .other(let name): results[name] ?? inImage
    }
  guard var buffer = try? vImage_Buffer(cgImage: image, format: format) else { return nil }
  if input == .sourceAlpha {
    // The bits of the mask are the components in memory from the first, so 0b1110 sets all but the fourth.
    let error = withUnsafeMutablePointer(to: &buffer) { buffer in
      vImageOverwriteChannelsWithScalar_ARGB8888(0, buffer, buffer, 0b1110, vImage_Flags(kvImageNoFlags))
    }
    guard error == kvImageNoError else {
      buffer.free()
      return nil
    }
  }
  return buffer
}

/// The input of a primitive converted to the format, as an image with its own copy of the pixels, or `nil` if it
/// can't be made.
func inputImage(
  _ input: SVGFilterInput?, format: vImage_CGImageFormat, srcImage: CGImage, inImage: CGImage,
  results: [String: CGImage]
) -> CGImage? {
  guard let buffer = inputBuffer(input, format: format, srcImage: srcImage, inImage: inImage, results: results)
  else { return nil }
  defer { buffer.free() }
  return try? buffer.createCGImage(format: format)
}
