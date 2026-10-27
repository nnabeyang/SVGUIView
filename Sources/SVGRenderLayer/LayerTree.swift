import QuartzCore
import SVGCore

extension RenderedContainer {
  /// Shows the layers in a layer, in place of the layers that it shows.
  ///
  /// The layers are made again each time, and change without animations.
  @MainActor
  package func show(in host: CALayer) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    host.sublayers = [makeLayer()]
    CATransaction.commit()
  }

  /// The layer of the container, with the layers in it.
  @MainActor
  private func makeLayer() -> CALayer {
    let layer = CALayer()
    layer.anchorPoint = .zero
    if let clip {
      // A container with a clip has no transform, so its bounds can be the clip, in the coordinates of the layer
      // around it.
      layer.bounds = clip
      layer.position = clip.origin
      layer.masksToBounds = true
    } else {
      layer.bounds = .zero
      layer.position = .zero
    }
    layer.setAffineTransform(transform)
    layer.opacity = Float(opacity)
    layer.allowsGroupOpacity = true
    layer.sublayers = children.map { child in
      switch child {
      case .container(let container): container.makeLayer()
      case .painted(let contents): contents.makeLayer()
      }
    }
    return layer
  }
}

extension PaintedContents {
  /// The layer that shows the image in its bounds, whose coordinates are the ones of the layer around it.
  @MainActor
  fileprivate func makeLayer() -> CALayer {
    let layer = CALayer()
    layer.anchorPoint = .zero
    layer.bounds = bounds
    layer.position = bounds.origin
    layer.contents = image
    layer.contentsScale = rasterScale
    layer.contentsGravity = .resize
    return layer
  }
}
