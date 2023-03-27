import UIKit

extension UIBezierPath {
    convenience init(roundedRect rect: CGRect, cornerSize: CGSize) {
        self.init()

        let rx = cornerSize.width
        let ry = cornerSize.height

        let x1 = rect.minX + rx
        let y1 = rect.minY + ry
        let x2 = rect.maxX - rx
        let y2 = rect.maxY - ry

        let cw = 4.0 * (sqrt(2.0) - 1.0) * rx / 3.0
        let ch = 4.0 * (sqrt(2.0) - 1.0) * ry / 3.0

        move(to: CGPoint(x: x1, y: y1 - ry))
        addLine(to: CGPoint(x: x2, y: y1 - ry))
        addCurve(to: .init(x: x2 + rx, y: y1),
                 controlPoint1: .init(x: x2 + cw, y: y1 - ry),
                 controlPoint2: .init(x: x2 + rx, y: y1 - ch))
        addLine(to: CGPoint(x: x2 + rx, y: rect.maxY - ry))
        addCurve(to: .init(x: x2, y: y2 + ry),
                 controlPoint1: .init(x: x2 + rx, y: y2 + ch),
                 controlPoint2: .init(x: x2 + cw, y: y2 + ry))
        addLine(to: CGPoint(x: rect.minX + rx, y: rect.maxY))
        addCurve(to: .init(x: x1 - rx, y: y2),
                 controlPoint1: .init(x: x1 - cw, y: y2 + ry),
                 controlPoint2: .init(x: x1 - rx, y: y2 + ch))
        addLine(to: CGPoint(x: x1 - rx, y: y1))
        addCurve(to: .init(x: x1, y: y1 - ry),
                 controlPoint1: .init(x: x1 - rx, y: y1 - ch),
                 controlPoint2: .init(x: x1 - cw, y: y1 - ry))
        close()
    }
}
