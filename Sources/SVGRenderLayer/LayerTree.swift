import QuartzCore
import SVGCore

/// The layers that show rendered layers in a host layer, which the layers of the next time reuse.
///
/// The layers of a time are matched with the ones of the previous time by their keys, and a layer that matches
/// changes only the values that differ, so that the layers of a moving element only change their transforms, and
/// contents that don't change aren't set again.
@MainActor
package final class LayerTree {
  /// The layer that the layers are shown in.
  package let host: CALayer
  /// The layers that show the latest rendered layers, by their keys.
  private var layers = [LayerKey: CALayer]()

  package init(host: CALayer) {
    self.host = host
  }

  /// Shows rendered layers in place of the ones that the host shows, without animations.
  package func show(_ contents: RenderedContainer) {
    var shown = [LayerKey: CALayer]()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let root = layer(of: contents, shown: &shown)
    if host.sublayers?.count != 1 || host.sublayers?.first !== root {
      host.sublayers = [root]
    }
    CATransaction.commit()
    layers = shown
  }

  /// Removes the layers that the host shows.
  package func clear() {
    host.sublayers = nil
    layers = [:]
  }

  /// The layer of a container, with the layers in it.
  private func layer(of container: RenderedContainer, shown: inout [LayerKey: CALayer]) -> CALayer {
    let layer = layers[container.key] ?? Self.makeLayer()
    shown[container.key] = layer
    if let clip = container.clip {
      // A container with a clip has no transform, so its bounds can be the clip, in the coordinates of the layer
      // around it.
      layer.set(bounds: clip)
      layer.masksToBounds = true
    } else {
      layer.set(bounds: .zero)
      layer.masksToBounds = false
    }
    if layer.affineTransform() != container.transform {
      layer.setAffineTransform(container.transform)
    }
    let opacity = Float(container.opacity)
    if layer.opacity != opacity {
      layer.opacity = opacity
    }
    let sublayers = container.children.map { child in
      switch child {
      case .container(let container): self.layer(of: container, shown: &shown)
      case .painted(let contents): self.layer(of: contents, shown: &shown)
      }
    }
    if layer.sublayers.map({ !$0.elementsEqual(sublayers, by: ===) }) ?? !sublayers.isEmpty {
      layer.sublayers = sublayers
    }
    return layer
  }

  /// The layer that shows the image of painted contents in their bounds, whose coordinates are the ones of the layer
  /// around it.
  private func layer(of contents: PaintedContents, shown: inout [LayerKey: CALayer]) -> CALayer {
    let layer = layers[contents.key] ?? Self.makeLayer()
    shown[contents.key] = layer
    layer.set(bounds: contents.bounds)
    // Setting the same image again would send it to the screen again.
    if (layer.contents as AnyObject?) !== contents.image {
      layer.contents = contents.image
    }
    // The image is resized to the bounds, so the scale only tells the screen how sharp it is.
    let contentsScale = max(contents.rasterScale.width, contents.rasterScale.height)
    if layer.contentsScale != contentsScale {
      layer.contentsScale = contentsScale
    }
    return layer
  }

  private static func makeLayer() -> CALayer {
    let layer = CALayer()
    layer.anchorPoint = .zero
    layer.allowsGroupOpacity = true
    layer.contentsGravity = .resize
    return layer
  }
}

extension CALayer {
  /// Sets the bounds, and the position that makes the coordinates of the layer the ones of the layer around it.
  fileprivate func set(bounds: CGRect) {
    if self.bounds != bounds {
      self.bounds = bounds
    }
    if position != bounds.origin {
      position = bounds.origin
    }
  }
}
