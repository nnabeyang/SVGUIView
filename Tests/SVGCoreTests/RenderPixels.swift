import CoreGraphics
import Testing

@testable import SVGCore

/// The pixels of a document rendered into a bitmap of 100 by 100.
func pixels(of base: SVGBaseContext) async throws -> [UInt8] {
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base, viewPort: rect, scale: 1).build(fit: fit))
  var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
  let context = try #require(
    CGContext(
      data: &pixels, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.concatenate(CGAffineTransform(1, 0, 0, -1, 0, 100))
  await CGPainterProxy.paint(tree, into: context)
  return pixels
}

/// Paints render trees without depending on SVGRenderCG, which the tests of SVGCore don't import: the shapes are
/// filled with their colors, which shows the computed values that the trees come from.
enum CGPainterProxy {
  static func paint(_ tree: RenderTree, into context: CGContext) async {
    for transform in tree.rootTransforms {
      context.concatenate(transform)
    }
    if let root = tree.root {
      paint(root, into: context)
    }
  }

  private static func paint(_ node: RenderNode, into context: CGContext) {
    context.saveGState()
    defer { context.restoreGState() }
    context.concatenate(node.transform)
    switch node {
    case .shape(let shape):
      guard let geometry = shape.geometry, case .vector(let fill, _, _)? = shape.content else { return }
      context.setAlpha(shape.opacity)
      if case .color(let color)? = fill {
        context.setFillColor(color)
        context.addPath(geometry.path.cgPath)
        context.fillPath()
      }
    case .group(let group):
      context.setAlpha(group.opacity)
      group.children.forEach { paint($0, into: context) }
    case .viewport(let viewport):
      context.concatenate(viewport.translation)
      if let content = viewport.content {
        context.concatenate(content.viewBoxTransform)
        content.children.forEach { paint($0, into: context) }
      }
    case .use(let use):
      if let instance = use.instance {
        context.concatenate(instance.translation)
        context.setAlpha(instance.opacity)
        instance.content.map { paint($0, into: context) }
      }
    case .filtered(let filtered):
      filtered.source.map { paint($0, into: context) }
    }
  }
}
