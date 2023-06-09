import os
import UIKit

public class SVGUIView: UIView {
    private let svg: SVGSVGElement
    private let pserver: SVGPaintServer
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")

    init(svg: SVGSVGElement, pserver: SVGPaintServer) {
        self.svg = svg
        self.pserver = pserver
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    public convenience init?(contentOf url: URL) {
        guard let (svg, paintServer) = Parser.parse(contentsOf: url) else { return nil }
        self.init(svg: svg, pserver: paintServer)
    }

    override public func layoutSubviews() {
        guard let superview = superview else {
            return
        }
        let size = superview.safeAreaLayoutGuide.layoutFrame.size
        let viewBox = svg.getViewBox(size: size)
        let transform = svg.getTransform(viewBox: viewBox, size: size)
        frame = viewBox.applying(transform)
    }

    override public func draw(_ rect: CGRect) {
        let viewBox = svg.getViewBox(size: rect.size)
        let transform = svg.getTransform(viewBox: viewBox, size: rect.size)
        let context = SVGContext(
            pserver: pserver,
            viewBox: viewBox,
            graphics: UIGraphicsGetCurrentContext()!,
            transform: transform
        )
        svg.draw(context)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
