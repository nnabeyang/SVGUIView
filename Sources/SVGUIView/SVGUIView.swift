import os
import UIKit

public class SVGUIView: UIView {
    private let svg: SVGSVGElement
    private let pserver: SVGPaintServer
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")

    init(frame: CGRect, svg: SVGSVGElement, pserver: SVGPaintServer) {
        self.svg = svg
        self.pserver = pserver
        super.init(frame: frame)
        backgroundColor = .clear
    }

    public convenience init?(contentOf url: URL) {
        guard let (svg, paintServer) = Parser.parse(contentsOf: url) else { return nil }
        let height = svg.height.value(total: .zero)
        let width = svg.width.value(total: .zero)
        self.init(frame: .init(origin: .zero,
                               size: CGSize(width: width, height: height)),
                  svg: svg, pserver: paintServer)
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
