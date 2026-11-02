import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Thins or fattens the input of a `feMorphology` in the color space of the primitive, and draws the result clipped
  /// to the subregion into `cgContext`.
  ///
  /// Each component of a pixel is the least or the greatest of that component in the rectangle of the radii around
  /// it, with transparent black outside the filter region. A radius of 0 doesn't change the input in its direction, as
  /// in Chrome and Safari, and a negative radius or radii that are both 0 leave the input as it is.
  func morphology(
    _ morphologyOperator: SVGMorphologyOperator, radius: CGSize, input: SVGFilterInput?,
    colorSpace: SVGColorInterpolation, srcImage: CGImage, inImage: CGImage, subregion: CGRect, bitmapRect: CGRect, opacity: CGFloat, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace,
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
    else { return nil }
    // `inputImage` swaps the buffers, so free each allocation through the pointer that it returns.
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format) else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    guard
      let selected = inputImage(
        input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
    else { return nil }
    var image = selected
    // The radii in pixels, which are the halves of the sides of the rectangle without its middle pixel.
    let radiusX = Int((radius.width * scale).rounded())
    let radiusY = Int((radius.height * scale).rounded())
    if radius.width >= 0, radius.height >= 0, radius.width > 0 || radius.height > 0 {
      guard let morphed = Self.morphed(selected, radiusX: radiusX, radiusY: radiusY, morphologyOperator, format: &format)
      else { return nil }
      image = morphed
    }
    cgContext.clip(to: subregion)
    cgContext.setAlpha(opacity)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  /// The least or the greatest components of an image in rectangles around its pixels, with transparent black
  /// outside it.
  private static func morphed(
    _ image: CGImage, radiusX: Int, radiusY: Int, _ morphologyOperator: SVGMorphologyOperator,
    format: inout vImage_CGImageFormat
  ) -> CGImage? {
    let width = image.width
    let height = image.height
    // The rectangle can't be larger than the image and the margins, which are as large as the image at most.
    let marginX = min(radiusX, width)
    let marginY = min(radiusY, height)
    guard var source = try? vImage_Buffer(width: width + 2 * marginX, height: height + 2 * marginY, bitsPerPixel: 32),
      var destination = try? vImage_Buffer(width: width, height: height, bitsPerPixel: 32)
    else { return nil }
    defer {
      source.free()
      destination.free()
    }
    // The image is in the middle of transparent margins, so that the rectangles of the pixels near its edges take
    // transparent black outside it.
    memset(source.data, 0, source.rowBytes * Int(source.height))
    guard let copied = try? vImage_Buffer(cgImage: image, format: format) else { return nil }
    defer { copied.free() }
    for y in 0..<height {
      memcpy(
        source.data.advanced(by: (y + marginY) * source.rowBytes + marginX * 4),
        copied.data.advanced(by: y * copied.rowBytes), width * 4)
    }
    let kernelWidth = vImagePixelCount(2 * marginX + 1)
    let kernelHeight = vImagePixelCount(2 * marginY + 1)
    let error =
      switch morphologyOperator {
      case .erode:
        vImageMin_ARGB8888(
          &source, &destination, nil, vImagePixelCount(marginX), vImagePixelCount(marginY), kernelHeight, kernelWidth,
          vImage_Flags(kvImageNoFlags))
      case .dilate:
        vImageMax_ARGB8888(
          &source, &destination, nil, vImagePixelCount(marginX), vImagePixelCount(marginY), kernelHeight, kernelWidth,
          vImage_Flags(kvImageNoFlags))
      }
    guard error == kvImageNoError else { return nil }
    return try? destination.createCGImage(format: format)
  }
}
