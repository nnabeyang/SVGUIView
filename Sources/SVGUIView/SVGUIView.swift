import os
import UIKit

public class SVGUIView: UIView {
    private var svg: SVGSVGElement
    private var pserver: SVGPaintServer
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")

    init(frame: CGRect, data: Data, svg: SVGSVGElement, pserver: SVGPaintServer) {
        self.data = data
        self.svg = svg
        self.pserver = pserver
        super.init(frame: frame)
        backgroundColor = .clear
    }

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    public convenience init?(data: Data) {
        guard let (svg, paintServer) = Parser.parse(data: data) else { return nil }
        self.init(frame: CGRect(origin: .zero, size: svg.size),
                  data: data, svg: svg, pserver: paintServer)
    }

    public var data: Data {
        didSet {
            guard let (svg, paintServer) = Parser.parse(data: data) else { return }
            self.svg = svg
            self.pserver = paintServer
            setNeedsDisplay()
        }
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

    override public var intrinsicContentSize: CGSize {
        svg.size
    }
}
