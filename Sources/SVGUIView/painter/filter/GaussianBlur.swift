import Accelerate
import CoreGraphics
import Foundation

extension GaussianBlurPrimitive {
  private static let maxKernelSize: UInt32 = 100

  private static func clampedToKernelSize(value: CGFloat, scale: CGFloat) -> UInt32 {
    let calculatedRadius = max(floor(value * 3.0 * sqrt(2 * .pi) / 4 + 0.5), 2 * scale)
    return min(Self.maxKernelSize, UInt32(calculatedRadius))
  }

  /// Blurs the input in the color space of the primitive, and draws it into `cgContext`.
  func apply(
    srcImage: CGImage, inImage: CGImage, subregion: CGRect, clipRect: inout CGRect, effectRect: CGRect,
    opacity: CGFloat, cgContext: CGContext, results: [String: CGImage], isFirst: Bool, scale: CGFloat
  ) -> CGImage? {
    let colorSpace: CGColorSpace
    switch input {
    case .none:
      if isFirst {
        colorSpace = (colorInterpolationFilters ?? filterColorInterpolationFilters ?? .sRGB).colorSpace
      } else {
        colorSpace = (colorInterpolationFilters ?? filterColorInterpolationFilters)?.colorSpace ?? inImage.colorSpace!
      }
    case .sourceAlpha, .sourceGraphic:
      colorSpace = colorInterpolationFilters?.colorSpace ?? srcImage.colorSpace!
    case .other(let srcName):
      if let image = results[srcName] {
        colorSpace = image.colorSpace!
      } else {
        colorSpace = colorInterpolationFilters?.colorSpace ?? (isFirst ? srcImage.colorSpace! : inImage.colorSpace!)
      }
    }
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: colorSpace,
        bitmapInfo: srcImage.bitmapInfo)
    else { return nil }
    // The buffers below share memory, so free each allocation once, through the pointer that it returns.
    guard let srcCopy = srcImage.copy(colorSpace: colorSpace),
      var srcBuffer = try? vImage_Buffer(cgImage: srcCopy, format: format)
    else { return nil }
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard let inputCopy = inImage.copy(colorSpace: colorSpace),
      var inputBuffer = try? vImage_Buffer(cgImage: inputCopy, format: format)
    else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }

    guard let data = malloc(inputBuffer.rowBytes * Int(inputBuffer.height)) else { return nil }
    var destBuffer = vImage_Buffer(data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
    defer {
      free(data)
    }
    var buffer = vImage_Buffer(data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
    let resultData = inputImageBuffer(input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer, destBuffer: &buffer)
    defer { free(resultData) }
    switch standardDeviation {
    case .hetero(let x, let y):
      guard x >= 0, y >= 0 else {
        swap(&inputBuffer, &destBuffer)
        break
      }
      if x != y {
        let kernelSizeX = Self.clampedToKernelSize(value: x * scale, scale: scale)
        let kernelSizeY = Self.clampedToKernelSize(value: y * scale, scale: scale)
        applyUnaccelerated(
          srcBuffer: &buffer, destBuffer: &destBuffer,
          kernelSizeX: kernelSizeX, kernelSizeY: kernelSizeY)
      } else {
        let kernelSize = Self.clampedToKernelSize(value: x * scale, scale: scale) | 1
        guard applyAccelerated(srcBuffer: &buffer, destBuffer: &destBuffer, kernelSize: kernelSize) else { return nil }
      }
    case .iso(let x):
      guard x >= 0 else {
        swap(&buffer, &destBuffer)
        break
      }
      let kernelSize = Self.clampedToKernelSize(value: x * scale, scale: scale) | 1
      guard applyAccelerated(srcBuffer: &buffer, destBuffer: &destBuffer, kernelSize: kernelSize) else { return nil }
    }
    // The image uses the memory of the buffer, which is freed after the image is drawn below.
    guard
      let image = vImageCreateCGImageFromBuffer(
        &destBuffer,
        &format,
        { _, _ in },
        nil,
        vImage_Flags(kvImageNoAllocate),
        nil)?.takeRetainedValue()
    else {
      return nil
    }
    clipRect = subregion
    cgContext.clip(to: subregion)
    cgContext.setAlpha(opacity)
    cgContext.draw(image, in: effectRect)
    return cgContext.makeImage()
  }

  /// Blurs `srcBuffer` into `destBuffer`, and returns `false` if the temporary buffer couldn't be allocated.
  private func applyAccelerated(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, kernelSize: UInt32) -> Bool {
    let tmpBufferSize = vImageBoxConvolve_ARGB8888(
      &srcBuffer,
      &destBuffer,
      nil,
      0,
      0,
      kernelSize,
      kernelSize,
      nil,
      vImage_Flags(kvImageEdgeExtend | kvImageGetTempBufferSize))
    // A negative size is an error code.
    guard tmpBufferSize >= 0, let tmpBuffer = malloc(tmpBufferSize) else { return false }
    vImageBoxConvolve_ARGB8888(
      &srcBuffer,
      &destBuffer,
      tmpBuffer,
      0,
      0,
      kernelSize,
      kernelSize,
      nil,
      vImage_Flags(kvImageEdgeExtend))
    vImageBoxConvolve_ARGB8888(
      &destBuffer,
      &srcBuffer,
      tmpBuffer,
      0,
      0,
      kernelSize,
      kernelSize,
      nil,
      vImage_Flags(kvImageEdgeExtend))
    vImageBoxConvolve_ARGB8888(
      &srcBuffer,
      &destBuffer,
      tmpBuffer,
      0,
      0,
      kernelSize,
      kernelSize,
      nil,
      vImage_Flags(kvImageEdgeExtend))
    free(tmpBuffer)
    return true
  }

  private func applyUnaccelerated(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, kernelSizeX: UInt32, kernelSizeY: UInt32) {
    var dxLeft = 0
    var dxRight = 0
    var dyLeft = 0
    var dyRight = 0
    var kernelSizeX = UInt(kernelSizeX)
    var kernelSizeY = UInt(kernelSizeY)
    let width = Int(srcBuffer.width)
    let height = Int(srcBuffer.height)
    let stride = srcBuffer.rowBytes
    var i = 0
    while i < 3 {
      if kernelSizeX > 0 {
        kernelPosition(blurIteration: i, radius: &kernelSizeX, deltaLeft: &dxLeft, deltaRight: &dxRight)
        boxBlur(
          srcBuffer: &srcBuffer, destBuffer: &destBuffer, dx: Int(kernelSizeX),
          dxLeft: dxLeft, dxRight: dxRight, stride: 4, strideLine: stride,
          width: width, height: height)
        swap(&srcBuffer, &destBuffer)
      }

      if kernelSizeY > 0 {
        kernelPosition(blurIteration: i, radius: &kernelSizeY, deltaLeft: &dyLeft, deltaRight: &dyRight)
        boxBlur(
          srcBuffer: &srcBuffer, destBuffer: &destBuffer, dx: Int(kernelSizeY),
          dxLeft: dyLeft, dxRight: dyRight, stride: stride, strideLine: 4,
          width: height, height: width)
        swap(&srcBuffer, &destBuffer)
      }
      i += 1
    }
  }

  private func boxBlur(
    srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, dx: Int, dxLeft: Int, dxRight: Int,
    stride: Int, strideLine: Int, width: Int, height: Int
  ) {
    let maxKernelSize = min(dxRight, Int(width))
    let srcData = srcBuffer.data.assumingMemoryBound(to: Pixel_8.self)
    let destData = destBuffer.data.assumingMemoryBound(to: Pixel_8.self)
    var y = 0
    while y < height {
      let line = y * strideLine
      var (sumR, sumG, sumB, sumA) = (Int(0), Int(0), Int(0), Int(0))
      var i = 0
      while i < maxKernelSize {
        let offset = line + i * stride
        sumR += Int(srcData[offset + 0])
        sumG += Int(srcData[offset + 1])
        sumB += Int(srcData[offset + 2])
        sumA += Int(srcData[offset + 3])
        i += 1
      }
      var x = 0
      while x < width {
        let offset = line + x * stride
        let destPtr = destData.advanced(by: offset)
        destPtr[0] = Pixel_8(max(sumR / dx, 0))
        destPtr[1] = Pixel_8(max(sumG / dx, 0))
        destPtr[2] = Pixel_8(max(sumB / dx, 0))
        destPtr[3] = Pixel_8(max(sumA / dx, 0))

        if x >= dxLeft {
          let leftOffset = offset - dxLeft * stride
          let srcPtr = srcData.advanced(by: leftOffset)
          sumR -= Int(srcPtr[0])
          sumG -= Int(srcPtr[1])
          sumB -= Int(srcPtr[2])
          sumA -= Int(srcPtr[3])
        }

        if x + dxRight < width {
          let rightOffset = offset + dxRight * stride
          let srcPtr = srcData.advanced(by: rightOffset)
          sumR += Int(srcPtr[0])
          sumG += Int(srcPtr[1])
          sumB += Int(srcPtr[2])
          sumA += Int(srcPtr[3])
        }
        x += 1
      }
      y += 1
    }
  }

  @inline(__always)
  private func kernelPosition(blurIteration: Int, radius: inout UInt, deltaLeft: inout Int, deltaRight: inout Int) {
    switch blurIteration {
    case 0:
      if radius % 2 == 1 {
        deltaLeft = Int(radius) / 2 - 1
        deltaRight = Int(radius) - deltaLeft
      } else {
        deltaLeft = Int(radius) / 2
        deltaRight = Int(radius) - deltaLeft
      }
    case 1:
      if radius % 2 == 1 {
        deltaLeft += 1
        deltaRight -= 1
      }
    case 2:
      if radius % 2 == 1 {
        deltaRight += 1
        radius += 1
      }
    default:
      fatalError()
    }
  }
}
