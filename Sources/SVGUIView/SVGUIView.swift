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
            baseContext = Parser.parse(data: data)
            guard let svg = baseContext.root else { return }
            self.svg = svg
            setNeedsDisplay()
        }
    }

    override public func draw(_ rect: CGRect) {
        guard let svg = baseContext.root else { return }
        let viewBox = svg.getViewBox(size: rect.size)
        let graphics = UIGraphicsGetCurrentContext()!
        let context = SVGContext(
            base: baseContext,
            graphics: graphics,
            viewPort: rect
        )
        context.saveGState()
        context.push(viewBox: viewBox)
        let height = (svg.height ?? .percent(100)).value(context: context, mode: .height)
        let width = (svg.width ?? .percent(100)).value(context: context, mode: .width)
        switch contentMode {
        case .scaleToFill:
            let scaleX = viewBox.width / width
            let scaleY = viewBox.height / height
            context.concatenate(CGAffineTransform(scaleX: scaleX, y: scaleY))
        default:
            break
        }

        let transform = getTransform(viewBox: viewBox, size: rect.size)
        context.concatenate(transform)
        switch contentMode {
        case .scaleAspectFill, .scaleAspectFit, .scaleToFill:
            let scale = viewBox.width / width
            context.concatenate(CGAffineTransform(scaleX: scale, y: scale))
        default:
            break
        }
        svg.draw(context, index: baseContext.contents.count - 1, depth: 1, mode: .root)
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
        let preserveAspectRatio: PreserveAspectRatio
        switch contentMode {
        case .scaleToFill, .redraw:
            preserveAspectRatio = .none
        case .scaleAspectFit:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet)
        case .scaleAspectFill:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .slice)
        case .center:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .mid, yAlign: .mid)
        case .top:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .mid, yAlign: .min)
        case .bottom:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .mid, yAlign: .max)
        case .left:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .min, yAlign: .mid)
        case .right:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .max, yAlign: .mid)
        case .topLeft:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .min, yAlign: .min)
        case .topRight:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .max, yAlign: .min)
        case .bottomLeft:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .min, yAlign: .max)
        case .bottomRight:
            preserveAspectRatio = PreserveAspectRatio(xAlign: .max, yAlign: .max)
        @unknown default:
            preserveAspectRatio = .none
        }
        return preserveAspectRatio.getTransform(viewBox: viewBox, size: size).translatedBy(x: viewBox.minX, y: viewBox.minY)
    }
}
