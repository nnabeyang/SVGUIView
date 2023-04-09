import SVGView
import UIKit

public extension SVGRect {
    func draw(_ trans: CGAffineTransform) {
        if width == 0 || height == 0 {
            return
        }
        let cornerSize = CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry))
        let rect = UIBezierPath(roundedRect: .init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
        let combined = transform.concatenating(trans)
        rect.apply(combined)
        applySVGFill(paint: fill, path: rect, transform: combined)
        applySVGStroke(stroke: stroke, rect: rect, scaled: sqrt(combined.a * combined.a + combined.b * combined.b))
    }

    private func applySVGStroke(stroke: SVGStroke?, rect: UIBezierPath, scaled: CGFloat) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        rect.lineWidth = stroke.width * scaled
        rect.lineCapStyle = stroke.cap
        rect.lineJoinStyle = stroke.join
        rect.stroke()
    }

    private func applySVGFill(paint: SVGPaint?, path: UIBezierPath, transform: CGAffineTransform) {
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
                let rect = CGRect(x: p.x1, y: p.y1, width: p.x2 - p.x1, height: p.y2 - p.y1).applying(transform)
                let (sx, sy): (CGFloat, CGFloat) = {
                    if p.userSpace {
                        return (1.0, 1.0)
                    }
                    if p.x1 == p.x2 || p.y1 == p.y2 {
                        return (width, height)
                    }
                    let s = min(width, height)
                    return (s, s)
                }()
                let rx = p.userSpace ? 1.0 : sx / width
                let ry = p.userSpace ? 1.0 : sy / height
                let x1 = rect.minX * sx
                let y1 = rect.minY * sy
                let x2 = rect.maxX * sx
                let y2 = rect.maxY * sy
                let x = x * rx
                let y = y * ry

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

                let pp = CGPointApplyAffineTransform(CGPoint(x: p.cx, y: p.cy), transform)

                let s = p.userSpace ? 1.0 : min(width, height)
                let rx = p.userSpace ? 1.0 : s / width
                let ry = p.userSpace ? 1.0 : s / height
                let cx = (pp.x * s + (p.userSpace ? 0 : x * rx))
                let cy = (pp.y * s + (p.userSpace ? 0 : y * ry))
                let r = p.r * s

                if !p.userSpace, width != height {
                    context.scaleBy(x: width / s, y: height / s)
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
                                               endRadius: max(width, height),
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
