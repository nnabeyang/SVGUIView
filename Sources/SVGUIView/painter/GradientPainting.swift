import CoreGraphics
import Foundation

extension GradientPaint {
  /// Paints the inside of a path with the gradient.
  func paint(_ path: CGPath, in graphics: CGContext) {
    switch self {
    case .linear(let gradient): gradient.paint(path, in: graphics)
    case .radial(let gradient): gradient.paint(path, in: graphics)
    }
  }
}

extension LinearGradientPaint {
  func paint(_ path: CGPath, in graphics: CGContext) {
    let gradientUnits = units
    let space = CGColorSpaceCreateDeviceRGB()
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else {
      return
    }
    let gContext = graphics
    gContext.saveGState()
    gContext.addPath(path)
    gContext.clip()
    let frame = path.boundingBoxOfPath
    let (sx, sy): (CGFloat, CGFloat) = {
      switch gradientUnits {
      case .userSpaceOnUse:
        return (1.0, 1.0)
      case .objectBoundingBox:
        if x1 == x2 || y1 == y2 {
          return (frame.width, frame.height)
        }
        let s = min(frame.width, frame.height)
        return (s, s)
      }
    }()
    let rect = CGRect(x: x1 * sx, y: y1 * sy, width: (x2 - x1) * sx, height: (y2 - y1) * sy)
    let rx: CGFloat
    let ry: CGFloat
    let x: CGFloat
    let y: CGFloat
    switch gradientUnits {
    case .userSpaceOnUse:
      rx = 1.0
      ry = 1.0
      x = 0
      y = 0
    case .objectBoundingBox:
      rx = sx / frame.width
      ry = sy / frame.height
      x = frame.minX * rx
      y = frame.minY * ry
    }
    let _x1 = rect.minX
    let _y1 = rect.minY
    let _x2 = rect.maxX
    let _y2 = rect.maxY

    if sx == sy {
      gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
    }

    switch spreadMethod {
    case .pad:
      let start = CGPoint(x: x + _x1, y: y + _y1)
      let end = CGPoint(x: x + _x2, y: y + _y2)
      let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
      gContext.drawLinearGradient(gradient, start: start, end: end, options: options)
    case .repeat:
      let dx = _x2 - _x1
      let dy = _y2 - _y1
      let n = min(ceil((x + _x1 - frame.minX) / dx), ceil((y + _y1 - frame.minY) / dy))
      let base = CGPoint(x: x + _x1 - dx * n, y: y + _y1 - dy * n)
      let m = min(ceil((frame.maxX - base.x) / dx), ceil((frame.maxY - base.y) / dy))
      for i in stride(from: 0, to: m, by: 1) {
        let start = CGPoint(x: base.x + i * dx, y: base.y + i * dy)
        let end = CGPoint(x: base.x + (i + 1) * dx, y: base.y + (i + 1) * dy)
        gContext.drawLinearGradient(gradient, start: start, end: end, options: [])
      }
    case .reflect:
      let reflected = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations.reversed())!
      let dx = _x2 - _x1
      let dy = _y2 - _y1
      let n = min(ceil((x + _x1 - frame.minX) / dx), ceil((y + _y1 - frame.minY) / dy))
      let base = CGPoint(x: x + _x1 - dx * n, y: y + _y1 - dy * n)
      let m = min(ceil((frame.maxX - base.x) / dx), ceil((frame.maxY - base.y) / dy))
      for i in stride(from: 0, to: m, by: 1) {
        let start = CGPoint(x: base.x + i * dx, y: base.y + i * dy)
        let end = CGPoint(x: base.x + (i + 1) * dx, y: base.y + (i + 1) * dy)
        if Int(i - n) % 2 == 0 {
          gContext.drawLinearGradient(gradient, start: start, end: end, options: [])
        } else {
          gContext.drawLinearGradient(reflected, start: start, end: end, options: [])
        }
      }
    }
    gContext.restoreGState()
  }
}

extension RadialGradientPaint {
  func paint(_ path: CGPath, in graphics: CGContext) {
    let gradientUnits = units
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!

    let gContext = graphics
    gContext.saveGState()
    gContext.addPath(path)
    gContext.clip()
    let frame = path.boundingBoxOfPath
    let pp = CGPoint(x: cx, y: cy)

    let s: CGFloat
    let rx: CGFloat
    let ry: CGFloat
    let _cx: CGFloat
    let _cy: CGFloat
    switch gradientUnits {
    case .userSpaceOnUse:
      s = 1.0
      rx = 1.0
      ry = 1.0
      _cx = pp.x * s
      _cy = pp.y * s
    case .objectBoundingBox:
      s = min(frame.width, frame.height)
      rx = s / frame.width
      ry = s / frame.height
      _cx = pp.x * s + frame.minX * rx
      _cy = pp.y * s + frame.minY * ry
    }
    let _r = r * s

    if case .objectBoundingBox = gradientUnits, frame.width != frame.height {
      gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
    }
    gContext.drawRadialGradient(
      gradient,
      startCenter: .init(x: _cx, y: _cy),
      startRadius: 0,
      endCenter: .init(x: _cx, y: _cy),
      endRadius: _r,
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    gContext.restoreGState()
  }
}
