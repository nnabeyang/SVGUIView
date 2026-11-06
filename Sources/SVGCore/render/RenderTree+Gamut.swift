import CoreGraphics

// Whether a tree paints colors outside sRGB is known when its nodes are made, so that a tree that reuses nodes of
// another time tells it without visiting them, and the rendering of every frame doesn't visit the whole tree.

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
  /// Whether the node paints colors outside sRGB, which a bitmap of a wide gamut shows.
  package var usesWideGamut: Bool {
    switch self {
    case .shape(let shape): shape.usesWideGamut
    case .group(let group): group.usesWideGamut
    case .viewport(let viewport): viewport.content?.usesWideGamut ?? false
    case .use(let use): use.instance?.usesWideGamut ?? false
    case .filtered: false
    }
  }
}

extension ShapeContent {
  var usesWideGamut: Bool {
    switch self {
    case .vector(let fill, let stroke, _):
      fill?.usesWideGamut == true || stroke?.paint.usesWideGamut == true
    case .image(let image, let stroke):
      image?.content.usesWideGamut == true || stroke?.paint.usesWideGamut == true
    case .colorGlyphs:
      false
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
