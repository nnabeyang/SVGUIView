import SVGView
import UIKit

public extension SVGRect {
    func draw(_ trans: CGAffineTransform) {
        if width == 0 || height == 0 {
            return
        }
        let cornerSize = CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry))
        let rect = UIBezierPath(roundedRect: .init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
        let combined = trans.concatenating(transform)
        rect.apply(combined)
        applySVGFill(paint: fill, rect: rect, transform: combined)
        applySVGStroke(stroke: stroke, rect: rect)
    }

    private func applySVGStroke(stroke: SVGStroke?, rect: UIBezierPath) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        rect.lineWidth = stroke.width
        rect.lineCapStyle = stroke.cap
        rect.lineJoinStyle = stroke.join
        rect.stroke()
    }

    private func applySVGFill(paint: SVGPaint?, rect: UIBezierPath, transform: CGAffineTransform) {
        if let paint = paint {
            switch paint {
            case let p as SVGLinearGradient:
                let colors = p.stops.map(\.color.toUIColor.cgColor) as CFArray
                let space = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat] = p.stops.map(\.offset)

                let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!

                let context = UIGraphicsGetCurrentContext()!
                context.addPath(rect.cgPath)
                context.clip()
                let x1 = p.x1 * width
                let y1 = p.y1 * height
                let x2 = p.x2 * width
                let y2 = p.y2 * height
                context.drawLinearGradient(gradient, start: CGPoint(x: x + x1, y: y + y1), end: CGPoint(x: x + x2, y: y + y2), options: [])
                context.resetClip()
            case let p as SVGRadialGradient:
                let colors = p.stops.map(\.color.toUIColor.cgColor) as CFArray
                p.stops.last?.color.toUIColor.setFill()
                rect.fill()
                let space = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat] = p.stops.map(\.offset)

                let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!

                let context = UIGraphicsGetCurrentContext()!
                context.addPath(rect.cgPath)
                context.clip()

                let pp = CGPointApplyAffineTransform(CGPoint(x: p.cx, y: p.cy), transform)

                let cx = pp.x
                let cy = pp.y
                context.drawRadialGradient(gradient,
                                           startCenter: .init(x: cx, y: cy),
                                           startRadius: 0,
                                           endCenter: .init(x: cx, y: cy),
                                           endRadius: p.r,
                                           options: [])
                context.resetClip()
            case let color as SVGColor:
                color.toUIColor.setFill()
                rect.fill()
            default:
                fatalError("Base SVGPaint is not convertable to UIView")
            }
        }
    }
}
