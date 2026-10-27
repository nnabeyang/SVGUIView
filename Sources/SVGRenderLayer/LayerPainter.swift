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
  /// The pixels of the image for each unit of the coordinates.
  package let rasterScale: CGFloat
  /// What the painted layer is in the plans of all times.
  package let key: LayerKey
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
  /// - Parameters:
  ///   - scale: The scale of the screen, which the bitmaps of clip paths, masks, filters and patterns are made at,
  ///     as in a rendering into one bitmap.
  ///   - previous: The layers of another time, whose contents the painted layers that don't change show instead of
  ///     being painted again.
  package func painted(scale: CGFloat, reusing previous: RenderedContainer? = nil) async -> RenderedContainer? {
    await painted(scale: scale, reusing: previous?.contentsByKey ?? [:])
  }

  private func painted(scale: CGFloat, reusing previous: [LayerKey: PaintedContents]) async -> RenderedContainer? {
    var children = [RenderedLayer]()
    for child in self.children {
      guard !Task.isCancelled else { return nil }
      switch child {
      case .container(let container):
        guard let painted = await container.painted(scale: scale, reusing: previous) else { return nil }
        children.append(.container(painted))
      case .painted(let layer):
        if !layer.changes, let contents = previous[layer.key], contents.bounds == layer.bounds,
          contents.rasterScale == layer.rasterScale
        {
          children.append(.painted(contents))
        } else {
          children.append(.painted(await layer.painted(scale: scale)))
        }
      }
    }
    guard !Task.isCancelled else { return nil }
    return RenderedContainer(
      id: id, transform: transform, opacity: opacity, clip: clip, children: children, key: key)
  }
}

extension PaintedLayer {
  /// What the nodes paint, as an image of the bounds at the raster scale.
  fileprivate func painted(scale: CGFloat) async -> PaintedContents {
    // Bounds on the pixels of the screen cover whole pixels, up to the error of the arithmetic that put them there.
    func pixels(_ length: CGFloat) -> CGFloat {
      let pixels = length * rasterScale
      return abs(pixels - pixels.rounded()) < 0.01 ? pixels.rounded() : pixels.rounded(.up)
    }
    let size = CGSize(width: pixels(bounds.width), height: pixels(bounds.height))
    // A bitmap that can't be made, such as one too large, shows nothing, as an element whose filter, mask, clip
    // path or pattern can't be allocated is left out of a rendering into one bitmap.
    guard let graphics = CGContext.bitmap(size: size, scale: 1, space: CGColorSpaceCreateDeviceRGB()) else {
      return PaintedContents(image: nil, bounds: bounds, rasterScale: rasterScale, key: key)
    }
    // The first row of the bitmap is the top of the image, as in the contents of a layer.
    graphics.concatenate(
      CGAffineTransform(size.width / bounds.width, 0, 0, -size.height / bounds.height, 0, size.height))
    graphics.translateBy(x: -bounds.minX, y: -bounds.minY)
    await CGPainter(scale: scale).paint(nodes, into: graphics)
    return PaintedContents(image: graphics.makeImage(), bounds: bounds, rasterScale: rasterScale, key: key)
  }
}
