import CoreGraphics

extension RenderTree {
  /// Whether the tree paints colors outside sRGB, which a bitmap of a wide gamut shows: colors of fills, strokes
  /// and gradients outside sRGB, and images of a wide gamut.
  ///
  /// The contents of filters, masks, clip paths and patterns aren't counted, since they're painted into bitmaps of
  /// sRGB.
  package var usesWideGamut: Bool {
    root?.usesWideGamut ?? false
  }
}

extension RenderNode {
  fileprivate var usesWideGamut: Bool {
    switch self {
    case .shape(let shape):
      switch shape.content {
      case .vector(let fill, let stroke, _):
        return fill?.usesWideGamut == true || stroke?.paint.usesWideGamut == true
      case .image(let image, let stroke):
        return image?.content.usesWideGamut == true || stroke?.paint.usesWideGamut == true
      case nil:
        return false
      }
    case .group(let group):
      return group.children.contains(where: \.usesWideGamut)
    case .viewport(let viewport):
      return viewport.content?.children.contains(where: \.usesWideGamut) ?? false
    case .use(let use):
      return use.instance?.content?.usesWideGamut ?? false
    case .filtered:
      return false
    }
  }
}

extension FillPaint {
  fileprivate var usesWideGamut: Bool {
    switch self {
    case .color(let color):
      color.isOutsideSRGB
    case .gradient(.linear(let gradient)?):
      gradient.colors.contains(where: \.isOutsideSRGB)
    case .gradient(.radial(let gradient)?):
      gradient.colors.contains(where: \.isOutsideSRGB)
    case .gradient(nil), .pattern:
      false
    }
  }
}

extension ImageContent {
  fileprivate var usesWideGamut: Bool {
    switch self {
    case .bitmap(let image): image.colorSpace?.isWideGamutRGB ?? false
    case .document(let node): node.usesWideGamut
    }
  }
}
