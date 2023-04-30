import os
import SVGView
import UIKit

public class SVGUIView: UIView {
    private let model: SVGViewport
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")
    init(model: SVGViewport) {
        self.model = model
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
        let viewBox = model.getViewBox(size: size)
        let transform = model.getTransform(viewBox: viewBox, size: size)
        frame = viewBox.applying(transform)
        model.transform = model.getTransform(viewBox: viewBox, size: frame.size)
    }

    override public func draw(_: CGRect) {
        model.draw()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
