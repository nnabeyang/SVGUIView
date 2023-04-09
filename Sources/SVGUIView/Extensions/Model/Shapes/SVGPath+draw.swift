import SVGView
import UIKit

extension SVGPath: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        let path = toBezierPath()
        let combined = transform.concatenating(trans)
        path.apply(combined)
        applySVGFill(paint: fill, path: path, transform: combined, frame: frame())
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
}
