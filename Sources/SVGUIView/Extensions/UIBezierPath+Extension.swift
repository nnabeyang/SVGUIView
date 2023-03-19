import UIKit

extension UIBezierPath {
    convenience init(roundedRect rect: CGRect, cornerSize: CGSize) {
        self.init()
        let x = rect.minX
        let y = rect.minY
        let rx = cornerSize.width
        let ry = cornerSize.height

        let x0 = rect.maxX - rx
        let y1 = rect.minY + ry
        let cw = 4.0 * (sqrt(2.0) - 1.0) * rx / 3.0
        let ch = 4.0 * (sqrt(2.0) - 1.0) * ry / 3.0

        move(to: CGPoint(x: x + rx, y: y))
        addLine(to: CGPoint(x: x0, y: y))
        addCurve(to: .init(x: x0 + rx, y: y + ry), controlPoint1: .init(x: x0 + cw, y: y), controlPoint2: .init(x: x0 + rx, y: y1 - ch))

        addLine(to: CGPoint(x: x0 + rx, y: rect.maxY - ry))

        let y2 = rect.maxY - ry
        addCurve(to: .init(x: x0, y: rect.maxY),
                 controlPoint1: .init(x: rect.maxX, y: y2 + ch),
                 controlPoint2: .init(x: x0 + cw, y: rect.maxY))

        addLine(to: CGPoint(x: rect.minX + rx, y: rect.maxY))

        let x3 = x + rx
        let y3 = rect.maxY - ry

        addCurve(to: .init(x: rect.minX, y: y3),
                 controlPoint1: .init(x: x3 - cw, y: rect.maxY),
                 controlPoint2: .init(x: rect.minX, y: y3 + ch))

        addLine(to: CGPoint(x: rect.minX, y: rect.minY + ry))

        let x4 = x + rx

        addCurve(to: .init(x: x4, y: rect.minY),
                 controlPoint1: .init(x: rect.minX, y: y1 - ch),
                 controlPoint2: .init(x: x4 - cw, y: rect.minY))
        close()
    }
}
