import SVGView
import UIKit

public extension SVGGroup {
    func draw() {
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
                content.draw()
            case let content as SVGText:
                content.draw()
            case let content as SVGDataImage:
                content.draw()
            case _ as SVGURLImage:
                SVGUIView.logger.debug("SVGUIView currently only support images in base64-encoded format.")
            default:
                fatalError("not implemented: \(type(of: node))")
            }
        }
        context.restoreGState()
    }
}
