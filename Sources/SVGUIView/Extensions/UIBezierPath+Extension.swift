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

        move(to: CGPoint(x: x1, y: y1 - ry))
        addLine(to: CGPoint(x: x2, y: y1 - ry))
        addEllipticalArc(withCenter: .init(x: x2, y: y1), radii: .init(width: rx * 2, height: ry * 2), startAngle: -CGFloat.pi / 2.0, endAngle: 0)
        addLine(to: CGPoint(x: x2 + rx, y: rect.maxY - ry))
        addEllipticalArc(withCenter: .init(x: x2, y: y2), radii: .init(width: rx * 2, height: ry * 2), startAngle: 0, endAngle: CGFloat.pi / 2.0)
        addLine(to: CGPoint(x: x1, y: y2 + ry))
        addEllipticalArc(withCenter: .init(x: x1, y: y2), radii: .init(width: rx * 2, height: ry * 2), startAngle: CGFloat.pi / 2.0, endAngle: CGFloat.pi)
        addLine(to: CGPoint(x: x1 - rx, y: y1))
        addEllipticalArc(withCenter: .init(x: x1, y: y1), radii: .init(width: rx * 2, height: ry * 2), startAngle: CGFloat.pi, endAngle: CGFloat.pi * 3.0 / 2.0)
        close()
    }
}
