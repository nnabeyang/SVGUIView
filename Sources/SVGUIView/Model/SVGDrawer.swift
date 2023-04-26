import SVGView
import UIKit

protocol SVG1DDrawer {
    var path: UIBezierPath? { get }
    var transform: CGAffineTransform { get }
    var stroke: SVGStroke? { get }
    var eoFill: Bool? { get }
    func draw(_ trans: CGAffineTransform)
    func applySVGStroke(stroke: SVGStroke?, path: UIBezierPath)
}

extension SVG1DDrawer {
    var eoFill: Bool? {
        nil
    }

    func draw(_ trans: CGAffineTransform) {
        guard let path = path else { return }
        let combined = transform.concatenating(trans)
        let context = UIGraphicsGetCurrentContext()!
        context.saveGState()
        context.concatenate(combined)
        applySVGStroke(stroke: stroke, path: path)
        context.restoreGState()
    }

    func applySVGStroke(stroke: SVGStroke?, path: UIBezierPath) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        path.setLineDash(stroke.dashes, count: stroke.dashes.count, phase: stroke.offset)
        path.lineWidth = stroke.width
        path.lineCapStyle = stroke.cap
        path.lineJoinStyle = stroke.join
        path.miterLimit = stroke.miterLimit
        path.stroke()
    }
}

protocol SVGDrawer: SVG1DDrawer {
    var fill: SVGPaint? { get }
    func frame() -> CGRect
    func applySVGFill(paint: SVGPaint?, path: UIBezierPath, frame: CGRect)
}

extension SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        guard let path = path else { return }
        let combined = transform.concatenating(trans)
        let context = UIGraphicsGetCurrentContext()!
        context.saveGState()
        context.concatenate(combined)
        applySVGFill(paint: fill, path: path, frame: frame())
        applySVGStroke(stroke: stroke, path: path)
        context.restoreGState()
    }

    func applySVGFill(paint: SVGPaint?, path: UIBezierPath, frame: CGRect) {
        if let eoFill = eoFill {
            path.usesEvenOddFillRule = eoFill
        }

        if let paint = paint {
            switch paint {
            case let p as SVGLinearGradient:
                let colors = p.stops.map(\.color.toUIColor.cgColor) as CFArray
                let space = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat] = p.stops.map(\.offset)
                let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!

                let context = UIGraphicsGetCurrentContext()!
                context.saveGState()
                context.addPath(path.cgPath)
                context.clip()
                let (sx, sy): (CGFloat, CGFloat) = {
                    if p.userSpace {
                        return (1.0, 1.0)
                    }
                    if p.x1 == p.x2 || p.y1 == p.y2 {
                        return (frame.width, frame.height)
                    }
                    let s = min(frame.width, frame.height)
                    return (s, s)
                }()
                let rect = CGRect(x: p.x1, y: p.y1, width: (p.x2 - p.x1) * sx, height: (p.y2 - p.y1) * sy)
                let rx = p.userSpace ? 1.0 : sx / frame.width
                let ry = p.userSpace ? 1.0 : sy / frame.height
                let x1 = rect.minX
                let y1 = rect.minY
                let x2 = rect.maxX
                let y2 = rect.maxY
                let x = frame.minX * rx
                let y = frame.minY * ry

                let start = CGPoint(x: x + x1, y: y + y1)
                let end = CGPoint(x: x + x2, y: y + y2)
                if sx == sy {
                    context.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
                }
                context.drawLinearGradient(gradient, start: start, end: end, options: [])
                context.restoreGState()
            case let p as SVGRadialGradient:
                let colors = p.stops.map(\.color.toUIColor.cgColor) as CFArray
                let space = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat] = p.stops.map(\.offset)

                let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!

                let context = UIGraphicsGetCurrentContext()!
                context.saveGState()
                context.addPath(path.cgPath)
                context.clip()

                let pp = CGPoint(x: p.cx, y: p.cy)

                let s = p.userSpace ? 1.0 : min(frame.width, frame.height)
                let rx = p.userSpace ? 1.0 : s / frame.width
                let ry = p.userSpace ? 1.0 : s / frame.height
                let cx = (pp.x * s + (p.userSpace ? 0 : frame.minX * rx))
                let cy = (pp.y * s + (p.userSpace ? 0 : frame.minY * ry))
                let r = p.r * s

                if !p.userSpace, frame.width != frame.height {
                    context.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
                }

                context.drawRadialGradient(gradient,
                                           startCenter: .init(x: cx, y: cy),
                                           startRadius: 0,
                                           endCenter: .init(x: cx, y: cy),
                                           endRadius: r,
                                           options: [])

                if let color = p.stops.last?.color.toUIColor.cgColor {
                    let space = CGColorSpaceCreateDeviceRGB()
                    let gradient = CGGradient(colorsSpace: space, colors: [color] as CFArray, locations: [1.0])!
                    context.drawRadialGradient(gradient,
                                               startCenter: .init(x: cx, y: cy),
                                               startRadius: r,
                                               endCenter: .init(x: cx, y: cy),
                                               endRadius: max(frame.width, frame.height),
                                               options: [])
                }

                context.restoreGState()
            case let color as SVGColor:
                color.toUIColor.setFill()
                path.fill()
            default:
                fatalError("Base SVGPaint is not convertable to UIView")
            }
        }
    }
}
