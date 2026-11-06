import CoreGraphics
import Foundation
import SVGCore

extension GradientPaint {
  /// Paints the inside of a path with the gradient, whose `objectBoundingBox` units are `frame`.
  func paint(_ path: CGPath, frame: CGRect, in graphics: CGContext) {
    switch self {
    case .linear(let gradient): gradient.paint(path, frame: frame, in: graphics)
    case .radial(let gradient): gradient.paint(path, frame: frame, in: graphics)
    }
  }
}

extension LinearGradientPaint {
  func paint(_ path: CGPath, frame units: CGRect, in graphics: CGContext) {
    let space = gradientSpace(colors: colors)
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else {
      return
    }
    // The bands of a repeated gradient cover the bounds of what's painted, which a stroke makes larger than the
    // bounds of its units.
    let frame = path.boundingBoxOfPath
    guard let transform = gradientTransform(self.transform, units: self.units, frame: units) else { return }
    graphics.saveGState()
    defer { graphics.restoreGState() }
    graphics.addPath(path)
    graphics.clip()
    graphics.concatenate(transform)

    let start = CGPoint(x: x1, y: y1)
    let vector = CGVector(dx: x2 - x1, dy: y2 - y1)
    let lengthSquared = vector.dx * vector.dx + vector.dy * vector.dy
    // The offsets along the vector of the corners of the path's bounding box, which the bands of a repeated
    // gradient cover.
    let inverse = transform.inverted()
    let offsets = [
      CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
      CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY),
    ].map {
      let point = $0.applying(inverse)
      return ((point.x - start.x) * vector.dx + (point.y - start.y) * vector.dy) / lengthSquared
    }
    let first = (offsets.min() ?? 0).rounded(.down)
    let last = (offsets.max() ?? 0).rounded(.up)
    // A gradient without a length, or with too many bands to draw, is padded.
    guard spreadMethod != .pad, lengthSquared > 0, last - first <= 1_000_000 else {
      let end = CGPoint(x: x2, y: y2)
      var options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
      if lengthSquared > 0, let padding = startPadding(colors: colors, locations: locations, space: space) {
        let before = CGPoint(x: start.x - vector.dx, y: start.y - vector.dy)
        graphics.drawLinearGradient(padding, start: before, end: start, options: .drawsBeforeStartLocation)
        options.remove(.drawsBeforeStartLocation)
      }
      graphics.drawLinearGradient(gradient, start: start, end: end, options: options)
      return
    }
    let reflected =
      spreadMethod == .reflect ? reflectedGradient(colors: colors, locations: locations, space: space) : nil
    for band in Int(first)..<Int(last) {
      let offset = CGFloat(band)
      let bandStart = CGPoint(x: start.x + vector.dx * offset, y: start.y + vector.dy * offset)
      let bandEnd = CGPoint(x: bandStart.x + vector.dx, y: bandStart.y + vector.dy)
      let bandGradient = band.isMultiple(of: 2) ? gradient : (reflected ?? gradient)
      graphics.drawLinearGradient(bandGradient, start: bandStart, end: bandEnd, options: [])
    }
  }
}

extension RadialGradientPaint {
  func paint(_ path: CGPath, frame: CGRect, in graphics: CGContext) {
    let space = gradientSpace(colors: colors)
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else {
      return
    }
    guard let transform = gradientTransform(self.transform, units: units, frame: frame) else { return }
    graphics.saveGState()
    defer { graphics.restoreGState() }
    graphics.addPath(path)
    graphics.clip()
    graphics.concatenate(transform)
    let center = CGPoint(x: cx, y: cy)
    let focus = CGPoint(x: fx, y: fy)
    // The circle at t goes from the focal circle at 0 to the end circle at 1, and on with the same steps.
    func circle(_ t: CGFloat) -> (center: CGPoint, radius: CGFloat) {
      (CGPoint(x: fx + (cx - fx) * t, y: fy + (cy - fy) * t), fr + (r - fr) * t)
    }
    // A circle covers a point when its radius is larger than the distance of the point from the focus and of the
    // center from the focus, which grow by `growth` with t. A focal circle that the end circle doesn't contain
    // makes a cone, which isn't repeated.
    let growth = r - fr - hypot(cx - fx, cy - fy)
    let inverse = transform.inverted()
    let bounds = path.boundingBoxOfPath
    let farthest =
      [
        CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
        CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
      ].map {
        let point = $0.applying(inverse)
        return hypot(point.x - focus.x, point.y - focus.y)
      }.max() ?? 0
    let last = growth > 0 ? ((farthest - fr) / growth).rounded(.up) : 0
    // A gradient that doesn't grow, or with too many bands to draw, is padded.
    // The inside of the focal circle takes the color at its start, which `padding` paints when CG would take
    // another color. A cone has no inside to pad.
    let padding = fr > 0 && growth > 0 ? startPadding(colors: colors, locations: locations, space: space) : nil
    if let padding {
      graphics.drawRadialGradient(
        padding, startCenter: focus, startRadius: 0, endCenter: focus, endRadius: fr, options: [])
    }
    let before: CGGradientDrawingOptions = padding == nil ? .drawsBeforeStartLocation : []
    guard spreadMethod != .pad, growth > 0, last <= 10_000 else {
      graphics.drawRadialGradient(
        gradient, startCenter: focus, startRadius: fr, endCenter: center, endRadius: r,
        options: before.union(.drawsAfterEndLocation))
      return
    }
    let reflected =
      spreadMethod == .reflect ? reflectedGradient(colors: colors, locations: locations, space: space) : nil
    for band in 0..<max(Int(last), 1) {
      let start = circle(CGFloat(band))
      let end = circle(CGFloat(band + 1))
      let bandGradient = band.isMultiple(of: 2) ? gradient : (reflected ?? gradient)
      graphics.drawRadialGradient(
        bandGradient, startCenter: start.center, startRadius: start.radius, endCenter: end.center,
        endRadius: end.radius, options: band == 0 ? before : [])
    }
  }
}

/// The color space that a gradient of colors interpolates in: device RGB, which is sRGB, or extended sRGB where a
/// color is outside sRGB, so that the gradient keeps it.
private func gradientSpace(colors: [CGColor]) -> CGColorSpace {
  colors.contains(where: \.isOutsideSRGB) ? extendedSRGB : CGColorSpaceCreateDeviceRGB()
}

private let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!

/// The gradient that goes from the end to the start of a gradient with the colors at the locations, which the odd
/// bands of a reflected gradient are painted with.
private func reflectedGradient(colors: [CGColor], locations: [CGFloat], space: CGColorSpace) -> CGGradient? {
  CGGradient(colorsSpace: space, colors: colors.reversed() as CFArray, locations: locations.reversed().map { 1 - $0 })
}

/// The gradient of the first color, which paints what's before the start of a gradient whose first stops share an
/// offset, or `nil` if they don't.
///
/// CG paints what's before the start with the last of the stops at the first offset, while SVG pads it with the
/// first stop.
private func startPadding(colors: [CGColor], locations: [CGFloat], space: CGColorSpace) -> CGGradient? {
  guard locations.count > 1, locations[0] == locations[1], let first = colors.first else { return nil }
  return CGGradient(colorsSpace: space, colors: [first, first] as CFArray, locations: [0, 1])
}

/// The transform from the coordinates of a gradient to user space, or `nil` if it can't be inverted, such as for
/// the bounding box of a path without a width or a height, which a gradient doesn't paint.
///
/// The gradient's own transform applies first, and then the transform of its units.
private func gradientTransform(
  _ gradientTransform: CGAffineTransform, units: SVGUnitType, frame: CGRect
) -> CGAffineTransform? {
  let transform: CGAffineTransform
  switch units {
  case .userSpaceOnUse:
    transform = gradientTransform
  case .objectBoundingBox:
    transform = gradientTransform.concatenating(
      CGAffineTransform(a: frame.width, b: 0, c: 0, d: frame.height, tx: frame.minX, ty: frame.minY))
  }
  return transform.a * transform.d - transform.b * transform.c != 0 ? transform : nil
}
