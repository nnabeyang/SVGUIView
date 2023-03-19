import SVGView
import UIKit

public extension SVGGroup {
    func append(to root: UIView) {
        for text in contents.filter({ $0 is SVGText }) {
            let view = text.toUIKit()
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            view.topAnchor.constraint(equalTo: root.topAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo: root.bottomAnchor).isActive = true
            view.leftAnchor.constraint(equalTo: root.leftAnchor).isActive = true
            view.rightAnchor.constraint(equalTo: root.rightAnchor).isActive = true
        }

        for group in contents.compactMap({ $0 as? SVGGroup }) {
            group.append(to: root)
        }
    }

    func draw(_ trans: CGAffineTransform) {
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
                content.draw(combined)
            case _ as SVGText:
                break
            default:
                fatalError("not implemented: \(type(of: node))")
            }
        }
    }
}
