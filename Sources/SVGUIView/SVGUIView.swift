import os
import UIKit

public class SVGUIView: UIView {
    private var svg: SVGSVGElement
    private var baseContext: SVGBaseContext
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")

    init(frame: CGRect, data: Data, svg: SVGSVGElement, baseContext: SVGBaseContext) {
        self.data = data
        self.svg = svg
        self.baseContext = baseContext
        super.init(frame: frame)
        backgroundColor = .clear
    }

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    public convenience init?(data: Data) {
        let baseContext = Parser.parse(data: data)
        guard let svg = baseContext.root else { return nil }
        self.init(frame: CGRect(origin: .zero, size: svg.size),
                  data: data, svg: svg, baseContext: baseContext)
    }

    public var data: Data {
        didSet {
            self.baseContext = Parser.parse(data: data)
            guard let svg = baseContext.root else { return }
            self.svg = svg
            self.frame = CGRect(origin: frame.origin, size: svg.size)
            setNeedsDisplay()
        }
    }

    override public func draw(_ rect: CGRect) {
        guard let svg = baseContext.root else { return }
        let viewBox = svg.getViewBox(size: rect.size)
        let graphics = UIGraphicsGetCurrentContext()!
        let context = SVGContext(
            base: baseContext,
            graphics: graphics
        )
        context.saveGState()
        let transform = getTransform(viewBox: viewBox, size: rect.size)
        context.concatenate(transform)
        let height = (svg.height ?? .percent(100)).value(total: viewBox.height)
        let width = (svg.width ?? .percent(100)).value(total: viewBox.width)
        let viewPortSize = CGSize(width: width, height: height)
        let scale = viewBox.size.width / viewPortSize.width
        context.concatenate(CGAffineTransform(scaleX: scale, y: scale))
        context.push(viewBox: viewBox)
        svg.draw(context, index: baseContext.contents.count - 1)
        context.popViewBox()
        context.restoreGState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        svg.size
    }

    func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let preserveAspectRatio = PreserveAspectRatio(xAlign: .mid, yAlign: .min, option: .meet)
        return preserveAspectRatio.getTransform(viewBox: viewBox, size: size).translatedBy(x: viewBox.minX, y: viewBox.minY)
    }
}
