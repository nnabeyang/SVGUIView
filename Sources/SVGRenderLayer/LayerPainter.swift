import CoreGraphics
import Foundation
import SVGCore
import SVGRenderCG

/// A layer of planned layers whose painted layers have been painted.
package indirect enum RenderedLayer: Sendable {
  case container(RenderedContainer)
  /// The contents of a painted layer, and the rectangle and the scale of the plan that they cover.
  case painted(PaintedContents)
}

/// A container layer whose painted layers have been painted.
package struct RenderedContainer: Sendable {
  /// The container layer, without the layers in it.
  package let id: RenderID?
  package let transform: CGAffineTransform
  package let opacity: CGFloat
  package let clip: CGRect?
  package let children: [RenderedLayer]
  /// What the container is in the plans of all times.
  package let key: LayerKey
}

/// The contents of a painted layer.
package struct PaintedContents: Sendable {
  /// The image of what the nodes paint, or `nil` if its bitmap couldn't be allocated, in which case the layer shows
  /// nothing.
  package let image: CGImage?
  /// The rectangle that the image covers, in the coordinates of the layer around this one.
  package let bounds: CGRect
  /// The pixels of the image for each unit of the coordinates along each axis.
  package let rasterScale: CGSize
  /// What the painted layer is in the plans of all times.
  package let key: LayerKey
  /// Whether the filter of the element that the layer paints ran on the GPU.
  package var filteredOnGPU = false
}

extension RenderedContainer {
  /// The contents of the painted layers in the container, at every depth, in order.
  package var paintedContents: [PaintedContents] {
    children.flatMap { child -> [PaintedContents] in
      switch child {
      case .container(let container): container.paintedContents
      case .painted(let contents): [contents]
      }
    }
  }

  /// How many painted layers were painted for these layers, instead of showing an image of the previous layers.
  package func paintedCount(since previous: RenderedContainer?) -> Int {
    let images = Set((previous?.paintedContents ?? []).compactMap(\.image).map(ObjectIdentifier.init))
    return paintedContents.count { contents in contents.image.map { !images.contains(ObjectIdentifier($0)) } ?? true }
  }

  /// The contents of the painted layers in the container, at every depth, by their keys.
  fileprivate var contentsByKey: [LayerKey: PaintedContents] {
    var contents = [LayerKey: PaintedContents]()
    for child in children {
      switch child {
      case .container(let container): contents.merge(container.contentsByKey) { $1 }
      case .painted(let painted): contents[painted.key] = painted
      }
    }
    return contents
  }
}

extension ContainerLayer {
  /// The container layer with its painted layers painted, in order, or `nil` if the task is cancelled.
  ///
  /// The layers whose filters run on the GPU are painted at the same time as each other and as the other layers, so
  /// that the waits for the GPU overlap.
  ///
  /// - Parameters:
  ///   - scale: The scale of the screen, which the bitmaps of clip paths, masks, filters and patterns are made at,
  ///     as in a rendering into one bitmap.
  ///   - previous: The layers of another time, whose contents the painted layers that don't change show instead of
  ///     being painted again.
  ///   - filters: The renderer that runs the filters of the layers that paint only an element with a filter on the
  ///     GPU, or `nil` to run them on the CPU.
  package func painted(
    scale: CGFloat, reusing previous: RenderedContainer? = nil, filters: MetalFilterRenderer? = nil
  ) async -> RenderedContainer? {
    let previous = previous?.contentsByKey ?? [:]
    let layers = paintedLayers.filter { $0.reusedContents(of: previous) == nil }
    let onGPU = filters.map { filters in layers.filter { $0.runsFilterOnGPU(filters, scale: scale) } } ?? []
    let onCPU = layers.filter { layer in !onGPU.contains { $0.key == layer.key } }
    let painted = await withTaskGroup(of: [LayerKey: PaintedContents].self) { group in
      for layer in onGPU {
        group.addTask { [layer.key: await layer.painted(scale: scale, filters: filters)] }
      }
      group.addTask {
        var painted = [LayerKey: PaintedContents]()
        for layer in onCPU {
          guard !Task.isCancelled else { break }
          painted[layer.key] = await layer.painted(scale: scale, filters: nil)
        }
        return painted
      }
      return await group.reduce(into: [:]) { $0.merge($1) { $1 } }
    }
    guard !Task.isCancelled else { return nil }
    return assembled(painted: painted, reusing: previous)
  }

  /// The painted layers in the container, at every depth, in order.
  private var paintedLayers: [PaintedLayer] {
    children.flatMap { child -> [PaintedLayer] in
      switch child {
      case .container(let container): container.paintedLayers
      case .painted(let layer): [layer]
      }
    }
  }

  /// The container with the contents of its painted layers, which are painted or reused.
  private func assembled(
    painted: [LayerKey: PaintedContents], reusing previous: [LayerKey: PaintedContents]
  ) -> RenderedContainer {
    let children = children.map { child -> RenderedLayer in
      switch child {
      case .container(let container):
        .container(container.assembled(painted: painted, reusing: previous))
      case .painted(let layer):
        .painted(
          layer.reusedContents(of: previous) ?? painted[layer.key]
            ?? PaintedContents(image: nil, bounds: layer.bounds, rasterScale: layer.rasterScale, key: layer.key))
      }
    }
    return RenderedContainer(
      id: id, transform: transform, opacity: opacity, clip: clip, children: children, key: key)
  }
}

extension PaintedLayer {
  /// The contents of another time that the layer shows instead of being painted again, if it doesn't change and they
  /// cover the same pixels.
  fileprivate func reusedContents(of previous: [LayerKey: PaintedContents]) -> PaintedContents? {
    guard !changes, let contents = previous[key], contents.bounds == bounds, contents.rasterScale == rasterScale
    else { return nil }
    return contents
  }

  /// The filter of the layer, if it paints only an element with a filter.
  private var filtered: FilteredNode? {
    guard nodes.count == 1, case .filtered(let filtered) = nodes[0] else { return nil }
    return filtered
  }

  /// Whether the layer paints only an element with a filter, which the renderer runs on the GPU.
  fileprivate func runsFilterOnGPU(_ filters: MetalFilterRenderer, scale: CGFloat) -> Bool {
    filtered.map { MetalFilterRenderer.supports($0, scale: scale) } ?? false
  }

  /// What the nodes paint, as an image of the bounds at the raster scale.
  ///
  /// The filter of a layer that paints only an element with a filter runs on the GPU when `filters` runs it.
  fileprivate func painted(scale: CGFloat, filters: MetalFilterRenderer?) async -> PaintedContents {
    // Bounds on the pixels of the screen cover whole pixels, up to the error of the arithmetic that put them there.
    func pixels(_ length: CGFloat, _ rasterScale: CGFloat) -> CGFloat {
      let pixels = length * rasterScale
      return abs(pixels - pixels.rounded()) < 0.01 ? pixels.rounded() : pixels.rounded(.up)
    }
    let size = CGSize(
      width: pixels(bounds.width, rasterScale.width), height: pixels(bounds.height, rasterScale.height))
    // A bitmap that can't be made, such as one too large, shows nothing, as an element whose filter, mask, clip
    // path or pattern can't be allocated is left out of a rendering into one bitmap.
    guard let graphics = CGContext.bitmap(size: size, scale: 1, space: CGColorSpaceCreateDeviceRGB()) else {
      return PaintedContents(image: nil, bounds: bounds, rasterScale: rasterScale, key: key)
    }
    // The first row of the bitmap is the top of the image, as in the contents of a layer.
    graphics.concatenate(
      CGAffineTransform(size.width / bounds.width, 0, 0, -size.height / bounds.height, 0, size.height))
    graphics.translateBy(x: -bounds.minX, y: -bounds.minY)
    let painter = CGPainter(scale: scale)
    if let filters, let filtered, let result = await filters.filterImage(of: filtered, painter: painter) {
      painter.draw(result, of: filtered, into: graphics)
      return PaintedContents(
        image: graphics.makeImage(), bounds: bounds, rasterScale: rasterScale, key: key, filteredOnGPU: true)
    }
    await painter.paint(nodes, into: graphics)
    return PaintedContents(image: graphics.makeImage(), bounds: bounds, rasterScale: rasterScale, key: key)
  }
}
