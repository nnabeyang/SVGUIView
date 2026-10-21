import Accelerate
import CoreGraphics

/// The image with the luminance of each pixel as its alpha, for a mask. Pixels with no alpha stay transparent.
func luminanceToAlpha(_ cgImage: CGImage) -> CGImage? {
  guard let sourceBuffer = try? vImage_Buffer(cgImage: cgImage) else {
    return nil
  }
  defer {
    sourceBuffer.free()
  }
  guard
    let format = vImage_CGImageFormat(
      bitsPerComponent: cgImage.bitsPerComponent,
      bitsPerPixel: cgImage.bitsPerPixel,
      colorSpace: cgImage.colorSpace!,
      bitmapInfo: cgImage.bitmapInfo)
  else {
    return nil
  }

  let srcPtr = sourceBuffer.data.assumingMemoryBound(to: Pixel_8.self)
  let width = sourceBuffer.width
  let height = sourceBuffer.height
  let pixelSize = width * height * 4
  var pixelOffset = 0
  while pixelOffset < pixelSize {
    let a = srcPtr[pixelOffset + 3]
    if a == 0 {
      pixelOffset += 4
      continue
    }
    let b = srcPtr[pixelOffset]
    let g = srcPtr[pixelOffset + 1]
    let r = srcPtr[pixelOffset + 2]

    let luma = (Double(r) * 0.2125 + Double(g) * 0.7154 + Double(b) * 0.0721)
    srcPtr[pixelOffset + 3] = Pixel_8(luma)
    pixelOffset += 4
  }
  return try? sourceBuffer.createCGImage(format: format)
}
