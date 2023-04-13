import SVGView
import UIKit

public extension SVGGroup {
    func draw(_ trans: CGAffineTransform, rect: CGRect) {
        let combined = trans.concatenating(transform)
        for node in contents {
            switch node {
            case let content as SVGLine:
                content.draw(combined)
            case let content as SVGCircle:
                content.draw(combined)
            case let content as SVGEllipse:
                content.draw(combined)
            case let content as SVGRect:
                content.draw(combined)
            case let content as SVGPolyline:
                content.draw(combined)
            case let content as SVGPath:
                content.draw(combined)
            case let content as SVGPolygon:
                content.draw(combined)
            case let content as SVGGroup:
                content.draw(combined, rect: rect)
            case let content as SVGText:
                content.draw(combined, rect: rect)
            default:
                fatalError("not implemented: \(type(of: node))")
            }
        }
    }
}
