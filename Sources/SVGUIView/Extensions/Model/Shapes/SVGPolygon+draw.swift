import SVGView
import UIKit

extension SVGPolygon: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        guard let poly = path else { return }
        let combined = transform.concatenating(trans)
        poly.apply(combined)
        applySVGFill(paint: fill, path: poly, transform: combined, frame: frame())
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
