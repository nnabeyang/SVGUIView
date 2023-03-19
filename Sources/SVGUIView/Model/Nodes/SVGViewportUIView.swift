import SVGView
import UIKit

public extension SVGViewport {
    func uiView() -> SVGUIViewportView {
        SVGUIViewportView(model: self)
    }
}

public class SVGUIViewportView: UIView {
    var model: SVGViewport
    private var trans: CGAffineTransform?
    init(model: SVGViewport) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    override public func layoutSubviews() {
        guard let superview = superview else {
            return
        }
        let size = superview.safeAreaLayoutGuide.layoutFrame.size
        let viewBox = getViewBox(size: size)
        bounds = viewBox
        transform = getTransform(viewBox: viewBox, size: size)

        for text in model.contents.filter({ $0 is SVGText }) {
            let view = text.toUIKit()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.topAnchor.constraint(equalTo: topAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            view.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            view.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        }

        for group in model.contents.compactMap({ $0 as? SVGGroup }) {
            group.append(to: self)
        }
    }

    override public func draw(_: CGRect) {
        for node in model.contents {
            switch node {
            case let content as SVGLine:
                content.draw(.identity)
            case let content as SVGCircle:
                content.draw(.identity)
            case let content as SVGEllipse:
                content.draw(.identity)
            case let content as SVGRect:
                content.draw(.identity)
            case let content as SVGPolyline:
                content.draw(.identity)
            case let content as SVGPath:
                content.draw(.identity)
            case let content as SVGPolygon:
                content.draw(.identity)
            case let content as SVGGroup:
                content.draw(.identity)
            case _ as SVGText:
                break
            default:
                fatalError("not implemented: \(type(of: node))")
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func getViewBox(size: CGSize) -> CGRect {
        if let viewBox = model.viewBox {
            return viewBox
        }
        return CGRect(x: 0,
                      y: 0,
                      width: model.width.toPixels(total: size.width),
                      height: model.height.toPixels(total: size.height))
    }

    private func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let transform = model.preserveAspectRatio.layout(size: viewBox.size, into: size)
        return transform.translatedBy(x: viewBox.width / 2.0, y: viewBox.height / 2.0)
    }
}

extension SVGLength {
    var ideal: CGFloat? {
        switch self {
        case .percent:
            return nil
        case let .pixels(pixels):
            return pixels
        }
    }
}
