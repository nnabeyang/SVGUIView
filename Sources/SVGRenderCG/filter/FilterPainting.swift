import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Paints an element with its filter.
  func paint(_ filtered: FilteredNode, into cgContext: CGContext) async {
    guard let source = await sourceImage(of: filtered), let result = await filterResult(of: filtered, source: source)
    else { return }
    await draw(result, of: filtered, into: cgContext)
  }

  /// Draws the result of a filter into its filter region with the transform of the element, clipped by its clip path,
  /// masked by its mask and with its opacity, in this order.
  ///
  /// The result covers the pixels of the filter bitmap, which can go past the filter region by part of a pixel.
  package func draw(_ result: CGImage, of filtered: FilteredNode, into cgContext: CGContext) async {
    cgContext.saveGState()
    cgContext.setBlendMode(filtered.blendMode)
    cgContext.concatenate(filtered.transform)
    // The clip path and the mask cover the filter region, which the result can go past the bounds of the element in.
    if let clip = filtered.clip {
      await apply(clip, to: cgContext, extent: filtered.effectRect)
    }
    switch filtered.mask {
    case .none:
      break
    case .clipToZero:
      cgContext.clip(to: .zero)
    case .mask(let mask):
      await apply(mask, to: cgContext, extent: filtered.effectRect)
    }
    cgContext.clip(to: filtered.effectRect)
    cgContext.setAlpha(filtered.opacity)
    cgContext.draw(result, in: bitmapRect(of: filtered))
    cgContext.restoreGState()
  }

  /// The rectangle that the bitmaps of a filter cover: the filter region, with its width and height rounded up to
  /// whole pixels at the scale, or the filter region if it has no pixel.
  ///
  /// The images of the filter are drawn into this rectangle, so that they're copied pixel for pixel rather than
  /// scaled a little.
  package func bitmapRect(of filtered: FilteredNode) -> CGRect {
    let rect = filtered.effectRect
    guard let (width, height, _) = CGContext.bitmapLayout(size: rect.size, scale: scale) else { return rect }
    return CGRect(x: rect.minX, y: rect.minY, width: CGFloat(width) / scale, height: CGFloat(height) / scale)
  }

  /// The element without its filter, painted into a bitmap of the filter region in the color space of
  /// `color-interpolation`, or `nil` if the bitmap can't be made or the task is cancelled.
  package func sourceImage(of filtered: FilteredNode) async -> CGImage? {
    guard
      let graphics = CGContext.bitmap(
        size: filtered.effectRect.size, scale: scale, space: filtered.colorInterpolation.colorSpace),
      await paintSource(of: filtered, into: graphics)
    else { return nil }
    return graphics.makeImage()
  }

  /// Paints the element without its filter into a cleared bitmap of the filter region at the scale, in the color
  /// space of `color-interpolation`, and returns `false` if the task is cancelled.
  package func paintSource(of filtered: FilteredNode, into graphics: CGContext) async -> Bool {
    let rect = filtered.effectRect
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -rect.minX, y: -rect.minY)
    graphics.saveGState()
    defer { graphics.restoreGState() }
    graphics.concatenate(transform)
    guard !Task.isCancelled else { return false }
    if let source = filtered.source {
      await paint(source, into: graphics)
    }
    return true
  }

  /// The result of the primitives of a filter on the image of the element from `sourceImage(of:)`, as an image of
  /// the filter region in the color space of `color-interpolation-filters`, or `nil` if its bitmap can't be made.
  ///
  /// A primitive whose result can't be made, or a cancelled task, ends the filter with the result of the primitives
  /// before it.
  package func filterResult(of filtered: FilteredNode, source srcImage: CGImage) async -> CGImage? {
    let effectRect = filtered.effectRect
    let bitmapRect = bitmapRect(of: filtered)
    guard
      let filterCgContext = CGContext.bitmap(
        size: effectRect.size, scale: scale, space: filtered.colorInterpolationFilters.colorSpace)
    else { return nil }
    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .translatedBy(x: -effectRect.minX, y: -effectRect.minY)
    filterCgContext.concatenate(transform)
    filterCgContext.saveGState()
    var results = [String: CGImage]()
    var inputImage = srcImage
    for step in filtered.primitives {
      // Leave the loop rather than return, so that the graphics states stay balanced. A cancelled rendering
      // throws its image away.
      if Task.isCancelled { break }
      await Task.yield()
      // Clear the bitmap without the clip of the primitive before.
      filterCgContext.restoreGState()
      filterCgContext.saveGState()
      filterCgContext.clear(bitmapRect)
      guard
        let clippedImage = apply(
          step, srcImage: srcImage, inImage: inputImage, bitmapRect: bitmapRect,
          cgContext: filterCgContext, results: results)
      else { break }
      if let result = step.result {
        results[result] = clippedImage
      }
      inputImage = clippedImage
      RenderingProgress.onFilterPrimitive?()
    }
    return inputImage
  }

  /// Applies a primitive to its inputs, drawing the result into `cgContext`, and returns the result clipped to the
  /// primitive subregion, or `nil` if it can't be made.
  ///
  /// - Parameter bitmapRect: The rectangle that the bitmaps of the filter cover, which the images are drawn into.
  private func apply(
    _ step: FilterStep, srcImage: CGImage, inImage: CGImage, bitmapRect: CGRect,
    cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    let subregion = step.subregion
    switch step.primitive {
    case .blend(let mode, let input, let input2):
      return blend(
        mode: mode, input: input, input2: input2, srcImage: srcImage, inImage: inImage, subregion: subregion,
        bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    case .colorMatrix(let input, let matrix):
      return colorMatrix(
        matrix, input: input, colorSpace: step.colorSpace, srcImage: srcImage, inImage: inImage, subregion: subregion,
        bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    case .componentTransfer(let input, let red, let green, let blue, let alpha):
      return componentTransfer(
        (red, green, blue, alpha), input: input, colorSpace: step.colorSpace, srcImage: srcImage, inImage: inImage,
        subregion: subregion, bitmapRect: bitmapRect, cgContext: cgContext,
        results: results)
    case .composite(let compositeOperator, let k, let input, let input2):
      return composite(
        compositeOperator, k: k, input: input, input2: input2, colorSpace: step.colorSpace, srcImage: srcImage,
        inImage: inImage, subregion: subregion, bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    case .morphology(let input, let morphologyOperator, let radius):
      return morphology(
        morphologyOperator, radius: radius, input: input, colorSpace: step.colorSpace, srcImage: srcImage,
        inImage: inImage, subregion: subregion, bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    case .tile(let input, let tile):
      return self.tile(
        tile, input: input, srcImage: srcImage, inImage: inImage, subregion: subregion,
        bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    case .flood(let color):
      return flood(
        color: color, srcImage: srcImage, inImage: inImage, subregion: subregion, bitmapRect: bitmapRect, cgContext: cgContext)
    case .gaussianBlur(let blur):
      return blur.apply(
        srcImage: srcImage, inImage: inImage, subregion: subregion, bitmapRect: bitmapRect,
        cgContext: cgContext, results: results, colorSpace: step.colorSpace, scale: scale)
    case .merge(let inputs):
      return merge(
        inputs: inputs, colorSpace: step.colorSpace, srcImage: srcImage, inImage: inImage, subregion: subregion,
        bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    case .offset(let input, let translation):
      return offset(
        translation: translation, input: input, srcImage: srcImage, inImage: inImage, subregion: subregion,
        bitmapRect: bitmapRect, cgContext: cgContext, results: results)
    }
  }

  private func blend(
    mode: CGBlendMode, input: SVGFilterInput?, input2: SVGFilterInput?, srcImage: CGImage, inImage: CGImage,
    subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext,
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
    // The subregion clips the result, rather than the inputs being drawn into it.
    cgContext.clip(to: subregion)
    cgContext.draw(image2, in: bitmapRect)
    cgContext.setBlendMode(mode)
    cgContext.draw(image1, in: bitmapRect)

    return cgContext.makeImage()
  }

  private func flood(
    color: [UInt8], srcImage: CGImage, inImage: CGImage, subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext
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
    cgContext.clip(to: subregion)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }

  private func merge(
    inputs: [SVGFilterInput?], colorSpace: SVGColorInterpolation, srcImage: CGImage, inImage: CGImage,
    subregion: CGRect, bitmapRect: CGRect, cgContext: CGContext,
    results: [String: CGImage]
  ) -> CGImage? {
    // The inputs are converted to the color space of the primitive, and composited in the bitmap of the filter.
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: colorSpace.colorSpace,
        bitmapInfo: srcImage.bitmapInfo),
      var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format)
    else { return nil }
    // `inputImage` swaps the buffers, so free each allocation through the pointer that it returns.
    let srcData = srcBuffer.data
    defer { free(srcData) }
    guard var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format) else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    // The subregion clips the result, rather than the inputs being drawn into it.
    cgContext.clip(to: subregion)

    for input in inputs {
      guard
        let image = inputImage(
          input: input, format: &format,
          results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
      else { return nil }
      cgContext.draw(image, in: bitmapRect)
    }
    return cgContext.makeImage()
  }

  /// Moves the input, clipped by the subregion.
  private func offset(
    translation: CGAffineTransform, input: SVGFilterInput?, srcImage: CGImage, inImage: CGImage, subregion: CGRect,
    bitmapRect: CGRect, cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    guard
      var format = vImage_CGImageFormat(
        bitsPerComponent: srcImage.bitsPerComponent,
        bitsPerPixel: srcImage.bitsPerPixel,
        colorSpace: srcImage.colorSpace!,
        bitmapInfo: srcImage.bitmapInfo),
      var inputBuffer = try? vImage_Buffer(cgImage: inImage, format: format)
    else { return nil }
    let inputData = inputBuffer.data
    defer { free(inputData) }
    let image: CGImage
    if let input {
      // `inputImage` swaps the buffers, so free each allocation through the pointer that it returns.
      guard var srcBuffer = try? vImage_Buffer(cgImage: srcImage, format: format) else { return nil }
      let srcData = srcBuffer.data
      defer { free(srcData) }
      guard
        let selected = inputImage(
          input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer)
      else { return nil }
      image = selected
    } else {
      // The image uses the memory of the buffer, which is freed after the image is drawn below.
      guard
        let previous = vImageCreateCGImageFromBuffer(
          &inputBuffer,
          &format,
          { _, _ in },
          nil,
          vImage_Flags(kvImageNoAllocate),
          nil)?.takeRetainedValue()
      else { return nil }
      image = previous
    }
    cgContext.clip(to: subregion)
    cgContext.concatenate(translation)
    cgContext.draw(image, in: bitmapRect)
    return cgContext.makeImage()
  }
}
