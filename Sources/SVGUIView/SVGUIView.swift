import SVGView
import UIKit
public struct SVGUIView {
    public private(set) var text = "Hello, World!"

    public init() {}
}

public extension SVGNode {
    func toUIKit() -> UIView {
        switch self {
        case let model as SVGViewport:
            return SVGUIViewportView(model: model)
        case let model as SVGText:
            return SVGTextUIView(model: model)
        default:
            fatalError("Base SVGNode is not convertable to UIKit:\(type(of: self))")
        }
    }
}
