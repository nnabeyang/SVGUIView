import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Paints an element with its filter.
  func paint(_ filtered: FilteredNode, into cgContext: CGContext) async {
    let effectRect = filtered.effectRect
    guard
      let imageCgContext = CGContext.bitmap(
        size: effectRect.size, scale: scale, space: filtered.colorInterpolation.colorSpace),
      let srcImage = await sourceImage(of: filtered, graphics: imageCgContext),
      let filterCgContext = CGContext.bitmap(
        size: effectRect.size, scale: scale, space: filtered.colorInterpolationFilters.colorSpace)
    else { return }
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -effectRect.minX, y: -effectRect.minY)
    filterCgContext.concatenate(transform)
    filterCgContext.saveGState()
    var results = [String: CGImage]()
    var inputImage = srcImage
    var clipRect = effectRect
    for step in filtered.primitives {
      // Leave the loop rather than return, so that the graphics states stay balanced. A cancelled rendering
      // throws its image away.
      if Task.isCancelled { break }
      await Task.yield()
      filterCgContext.clear(effectRect)
      filterCgContext.restoreGState()
      filterCgContext.saveGState()
      guard
        let clippedImage = apply(
          step, srcImage: srcImage, inImage: inputImage, clipRect: &clipRect, effectRect: effectRect,
          opacity: filtered.opacity, cgContext: filterCgContext, results: results)
      else { break }
      if let result = step.result {
        results[result] = clippedImage
      }
      inputImage = clippedImage
    }
    cgContext.saveGState()
    cgContext.concatenate(filtered.transform)
    cgContext.draw(inputImage, in: effectRect)
    cgContext.restoreGState()
  }

  /// The element without its filter, painted into the bitmap of the filter region.
  private func sourceImage(of filtered: FilteredNode, graphics: CGContext) async -> CGImage? {
    let rect = filtered.effectRect
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -rect.minX, y: -rect.minY)
    graphics.concatenate(transform)

    graphics.saveGState()
    guard !Task.isCancelled else { return nil }
    if let source = filtered.source {
      await paint(source, into: graphics)
    }
    guard let image = graphics.makeImage() else { return nil }
    graphics.restoreGState()
    return image
  }

  /// Applies a primitive to its inputs, drawing the result into `cgContext`, and returns the result clipped to the
  /// primitive subregion, or `nil` if it can't be made.
  private func apply(
    _ step: FilterStep, srcImage: CGImage, inImage: CGImage, clipRect: inout CGRect, effectRect: CGRect,
    opacity: CGFloat, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    let subregion = step.subregion
    switch step.primitive {
    case .blend(let mode, let input, let input2):
      return blend(
        mode: mode, input: input, input2: input2, srcImage: srcImage, inImage: inImage, subregion: subregion,
        clipRect: &clipRect, effectRect: effectRect, opacity: opacity, cgContext: cgContext, results: results)
    case .flood(let color):
      return flood(
        color: color, srcImage: srcImage, inImage: inImage, subregion: subregion, clipRect: &clipRect,
        effectRect: effectRect, opacity: opacity, cgContext: cgContext)
    case .gaussianBlur(let blur):
      return blur.apply(
        srcImage: srcImage, inImage: inImage, subregion: subregion, clipRect: &clipRect, effectRect: effectRect,
        opacity: opacity, cgContext: cgContext, results: results, isFirst: step.isFirst, scale: scale)
    case .merge(let inputs, let colorInterpolationFilters):
      return merge(
        inputs: inputs, colorInterpolationFilters: colorInterpolationFilters, srcImage: srcImage, inImage: inImage,
        subregion: subregion, clipRect: &clipRect, opacity: opacity, cgContext: cgContext, results: results,
        isFirst: step.isFirst)
    case .offset(let translation):
      return offset(
        translation: translation, srcImage: srcImage, inImage: inImage, subregion: subregion, clipRect: &clipRect,
        effectRect: effectRect, opacity: opacity, cgContext: cgContext)
    }
  }

  private func blend(
    mode: CGBlendMode, input: SVGFilterInput?, input2: SVGFilterInput?, srcImage: CGImage, inImage: CGImage,
    subregion: CGRect, clipRect: inout CGRect, effectRect: CGRect, opacity: CGFloat, cgContext: CGContext,
    results: [String: CGImage]
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
    else { return nil }
    // `inputImage` swaps the buffers, so free each allocation through the pointer that it returns.
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format) else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    guard
      let image1 = inputImage(
        input: input, format: &format,
        results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer),
      let image2 = inputImage(
        input: input2, format: &format,
        results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
    else { return nil }
    cgContext.setAlpha(opacity)
    cgContext.draw(image2, in: subregion)
    cgContext.setBlendMode(mode)
    cgContext.draw(image1, in: effectRect)

    clipRect = subregion
    cgContext.clip(to: subregion)
    return cgContext.makeImage()
  }

  private func flood(
    color: [UInt8], srcImage: CGImage, inImage: CGImage, subregion: CGRect, clipRect: inout CGRect,
    effectRect: CGRect, opacity: CGFloat, cgContext: CGContext
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format)
    else { return nil }
    defer { inputBuffer.free() }
    var color = color
    vImageBufferFill_ARGB8888(
      &inputBuffer,
      &color,
      vImage_Flags(kvImageNoFlags))

    // The image uses the memory of the buffer, which is freed after the image is drawn below.
    guard
      let image = vImageCreateCGImageFromBuffer(
        &inputBuffer,
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

  private func merge(
    inputs: [SVGFilterInput?], colorInterpolationFilters: SVGColorInterpolation?, srcImage: CGImage,
    inImage: CGImage, subregion: CGRect, clipRect: inout CGRect, opacity: CGFloat, cgContext: CGContext,
    results: [String: CGImage], isFirst: Bool
  ) -> CGImage? {
    let colorSpace = colorInterpolationFilters?.colorSpace ?? (isFirst ? srcImage.colorSpace! : inImage.colorSpace!)
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: colorSpace,
        bitmapInfo: srcImage.bitmapInfo),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
    else { return nil }
    // `inputImage` swaps the buffers, so free each allocation through the pointer that it returns.
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format) else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    cgContext.setAlpha(opacity)

    for input in inputs {
      guard
        let image = inputImage(
          input: input, format: &format,
          results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
      else { return nil }
      cgContext.draw(image, in: subregion)
    }
    clipRect = subregion
    cgContext.clip(to: subregion)
    return cgContext.makeImage()
  }

  private func offset(
    translation: CGAffineTransform, srcImage: CGImage, inImage: CGImage, subregion: CGRect, clipRect: inout CGRect,
    effectRect: CGRect, opacity: CGFloat, cgContext: CGContext
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format)
    else { return nil }
    defer { inputBuffer.free() }
    // The image uses the memory of the buffer, which is freed after the image is drawn below.
    guard
      let image = vImageCreateCGImageFromBuffer(
        &inputBuffer,
        &format,
        { _, _ in },
        nil,
        vImage_Flags(kvImageNoAllocate),
        nil)?.takeRetainedValue()
    else { return nil }
    clipRect = CGRectIntersection(clipRect, subregion)
    cgContext.clip(to: clipRect)
    cgContext.concatenate(translation)
    cgContext.setAlpha(opacity)
    cgContext.draw(image, in: effectRect)
    return cgContext.makeImage()
  }
}
