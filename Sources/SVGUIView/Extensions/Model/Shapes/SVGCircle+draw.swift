import SVGView
import UIKit

public extension SVGCircle {
    func draw(_ trans: CGAffineTransform) {
        let circle = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: true)
        circle.apply(trans.concatenating(transform))
        applySVGFill(paint: fill, path: circle)
        applySVGStroke(stroke: stroke, path: circle)
    }

    private func applySVGStroke(stroke: SVGStroke?, path: UIBezierPath) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        path.lineWidth = stroke.width
        path.lineCapStyle = stroke.cap
        path.lineJoinStyle = stroke.join
        path.stroke()
    }

    private func applySVGFill(paint: SVGPaint?, path rect: UIBezierPath) {
        if let paint = paint {
            switch paint {
            case let p as SVGLinearGradient:
                let colors = p.stops.map(\.color.toUIColor.cgColor) as CFArray
                let space = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat] = p.stops.map(\.offset)

                let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!

                let context = UIGraphicsGetCurrentContext()!
                context.resetClip()
                context.addPath(rect.cgPath)
                context.clip()
                let x = cx - r
                let y = cy - r
                let x1 = p.x1 * r * 2
                let y1 = p.y1 * r * 2
                let x2 = p.x2 * r * 2
                let y2 = p.y2 * r * 2
                context.drawLinearGradient(gradient, start: CGPoint(x: x + x1, y: y + y1), end: CGPoint(x: x + x2, y: y + y2), options: [])
            case let p as SVGRadialGradient:
                let colors = p.stops.map(\.color.toUIColor.cgColor) as CFArray
                let space = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat] = p.stops.map(\.offset)

                let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!

                let context = UIGraphicsGetCurrentContext()!
                context.resetClip()
                context.addPath(rect.cgPath)
                context.clip()
                let r = p.r
                let cx = p.cx
                let cy = p.cy
                context.drawRadialGradient(gradient,
                                           startCenter: .init(x: cx, y: cy),
                                           startRadius: 0,
                                           endCenter: .init(x: cx, y: cy),
                                           endRadius: r * self.r,
                                           options: [])
            case let color as SVGColor:
                color.toUIColor.setFill()
                rect.fill()
            default:
                fatalError("Base SVGPaint is not convertable to UIView")
            }
        }
    }
}
