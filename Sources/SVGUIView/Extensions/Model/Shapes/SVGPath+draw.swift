import SVGView
import UIKit

public extension SVGPath {
    func draw(_ beforeTransform: CGAffineTransform) {
        let path = toBezierPath()
        path.apply(beforeTransform)
        path.apply(transform)
        applySVGFill(paint: fill, path: path)
        applySVGStroke(stroke: stroke, path: path)
    }

    private func applySVGStroke(stroke: SVGStroke?, path: UIBezierPath) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        path.lineWidth = stroke.width
        path.miterLimit = stroke.miterLimit
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
}
