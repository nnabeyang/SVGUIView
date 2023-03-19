import SVGView
import UIKit

public extension SVGPolygon {
    func draw(_ trans: CGAffineTransform) {
        guard let poly = path else { return }
        poly.apply(trans.concatenating(transform))
        applySVGFill(paint: fill, path: poly)
        applySVGStroke(stroke: stroke, path: poly)
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

    private func applySVGFill(paint: SVGPaint?, path: UIBezierPath) {
        if let p = paint as? SVGColor {
            p.toUIColor.setFill()
            path.fill()
        }
    }

    private var path: MBezierPath? {
        guard let first = points.first else { return nil }
        let path = MBezierPath()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for i in 1 ..< points.count {
            let point = points[i]
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        path.close()
        return path
    }
}
