import os
import SVGView
import UIKit

public class SVGUIView: UIView {
    private let model: SVGViewport
    private let group: SVGGroup
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")
    init(model: SVGViewport) {
        self.model = model
        group = SVGGroup(contents: model.contents)
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    public convenience init?(contentOf url: URL) {
        guard let data = try? Data(contentsOf: url),
              let node = SVGParser.parse(data: data),
              let model = node as? SVGViewport else { return nil }
        self.init(model: model)
    }

    override public func layoutSubviews() {
        guard let superview = superview else {
            return
        }
        let size = superview.safeAreaLayoutGuide.layoutFrame.size
        let viewBox = getViewBox(size: size)
        bounds = viewBox
        transform = getTransform(viewBox: viewBox, size: size)
    }

    override public func draw(_: CGRect) {
        group.draw()
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
