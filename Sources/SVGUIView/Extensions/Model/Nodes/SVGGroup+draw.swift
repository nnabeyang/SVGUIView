import SVGView
import UIKit

public extension SVGGroup {
    func draw(rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!
        context.saveGState()
        context.concatenate(transform)
        for node in contents {
            switch node {
            case let content as SVGLine:
                content.draw()
            case let content as SVGCircle:
                content.draw()
            case let content as SVGEllipse:
                content.draw()
            case let content as SVGRect:
                content.draw()
            case let content as SVGPolyline:
                content.draw()
            case let content as SVGPath:
                content.draw()
            case let content as SVGPolygon:
                content.draw()
            case let content as SVGGroup:
                content.draw(rect: rect)
            case let content as SVGText:
                content.draw(rect: rect)
            default:
                fatalError("not implemented: \(type(of: node))")
            }
        }
        context.restoreGState()
    }
}
