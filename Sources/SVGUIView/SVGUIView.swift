import os
import UIKit

public class SVGUIView: UIView {
    private var baseContext: SVGBaseContext
    private let taskManager = TaskManager()
    static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    init(frame: CGRect, baseContext: SVGBaseContext, data: Data = Data()) {
        self.data = data
        self.baseContext = baseContext
        super.init(frame: frame)
        backgroundColor = .clear
    }

    public convenience init(frame: CGRect, data: Data? = nil) {
        let data = data ?? Data()
        let baseContext = Parser.parse(data: data)
        self.init(frame: frame, baseContext: baseContext, data: data)
    }

    public convenience init(data: Data = Data()) {
        let baseContext = Parser.parse(data: data)
        let size = baseContext.root?.size ?? .zero
        self.init(frame: .init(origin: .zero, size: size), baseContext: baseContext, data: data)
    }

    public var data: Data {
        didSet {
            Task {
                if let task = await taskManager.task {
                    while !task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1 * NSEC_PER_MSEC)
                    }
                    await taskManager.shiftTask()
                }
                baseContext = Parser.parse(data: data)
                guard baseContext.root != nil else { return }
                setNeedsDisplay()
            }
        }
    }

    override public func draw(_ rect: CGRect) {
        Task {
            await taskManager.add(task: Task.detached(priority: .medium) {
                let image = await self.makeCGImage(rect: rect)
                await MainActor.run {
                    self.layer.contents = image
                }
                await self.taskManager.startRendering()
            })
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var svg: SVGSVGElement? {
        baseContext.root
    }

    override public var intrinsicContentSize: CGSize {
        svg?.size ?? .zero
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

    public func takeSnapshot(rect: CGRect? = nil) async -> UIImage? {
        await makeCGImage(rect: rect).flatMap { UIImage(cgImage: $0) }
    }

    private func makeCGImage(rect: CGRect? = nil) async -> CGImage? {
        let rect = rect ?? frame
        let scale = UIScreen.main.scale
        guard let svg = baseContext.root else { return nil }
        let viewBox = svg.getViewBox(size: rect.size)

        let frameWidth = Int((rect.width * scale).rounded(.up))
        let frameHeight = Int((rect.height * scale).rounded(.up))
        let bytesPerRow = 4 * frameWidth

        let graphics = CGContext(data: nil,
                                 width: frameWidth,
                                 height: frameHeight,
                                 bitsPerComponent: 8,
                                 bytesPerRow: bytesPerRow,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)!
        graphics.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, CGFloat(frameHeight)))

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
        return await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                await svg.draw(context, index: self.baseContext.contents.count - 1, mode: .root)
                context.popViewBox()
                context.restoreGState()
                guard !Task.isCancelled else { return nil }
                return graphics.makeImage()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
                return nil
            }
            defer {
                group.cancelAll()
            }
            guard let image = await group.next() else {
                return nil
            }
            return image
        }
    }
}

private actor TaskManager {
    private var tasks: [Task<Void, Never>]
    init() {
        tasks = []
    }

    var task: Task<Void, Never>? {
        tasks.first
    }

    func add(task: Task<Void, Never>) {
        tasks.append(task)
    }

    func shiftTask() {
        guard !tasks.isEmpty else { return }
        tasks.removeFirst()
    }

    func startRendering() {
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateContents)
        )
        displayLink.add(to: .main, forMode: .common)
    }

    @objc
    private nonisolated func updateContents(_ displayLink: CADisplayLink) {
        displayLink.invalidate()
        Task {
            if let task = await task {
                task.cancel()
            }
        }
    }
}
