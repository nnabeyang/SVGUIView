public import UIKit
import os

/// A view that displays a single SVG image.
///
/// The view parses SVG data and renders it in a background task. Assign new data
/// to ``data`` to change the displayed image. The view renders again when its
/// size or its `contentMode` changes.
public class SVGUIView: UIView {
  private var baseContext: SVGBaseContext
  private let taskManager = TaskManager()
  /// The settings that control background rendering.
  public var configuration: SVGUIViewConfiguration = .init()
  static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")
  /// The size that the view last rendered at, so that it renders again when its size changes.
  private var renderedSize: CGSize?
  /// Counts the renderings that the view starts, so that one that finishes after a newer one is not shown.
  private var renderingGeneration = 0

  /// Creates a view that displays the SVG file at the given URL.
  ///
  /// The view's frame is sized to the SVG document's `width` and `height`.
  ///
  /// - Parameter url: The URL of an SVG file. The file is read synchronously.
  /// - Returns: `nil` if the file cannot be read.
  public convenience init?(contentsOf url: URL) {
    guard let data = try? Data(contentsOf: url) else { return nil }
    self.init(data: data)
  }

  init(frame: CGRect, baseContext: SVGBaseContext, data: Data = Data()) {
    self.data = data
    self.baseContext = baseContext
    super.init(frame: frame)
    backgroundColor = .clear
    setNeedsDisplay()
  }

  /// Creates a view with the given frame that displays the given SVG data.
  ///
  /// - Parameters:
  ///   - frame: The frame rectangle for the view.
  ///   - data: The SVG data to display. Pass `nil` to create an empty view.
  public convenience init(frame: CGRect, data: Data? = nil) {
    let data = data ?? Data()
    let baseContext = SVGParser.parse(data: data)
    self.init(frame: frame, baseContext: baseContext, data: data)
  }

  /// Creates a view that displays the given SVG data.
  ///
  /// The view's frame is sized to the SVG document's `width` and `height`.
  ///
  /// - Parameter data: The SVG data to display.
  public convenience init(data: Data = Data()) {
    let baseContext = SVGParser.parse(data: data)
    let size = baseContext.root?.size ?? .zero
    self.init(frame: .init(origin: .zero, size: size), baseContext: baseContext, data: data)
  }

  /// The SVG data that the view displays.
  ///
  /// Setting this property parses the new data and redraws the view
  /// asynchronously. Setting the data that the view already displays does
  /// nothing.
  public var data: Data {
    didSet {
      // SVGView sets its data on every update of the SwiftUI view.
      guard data != oldValue else { return }
      Task {
        if await !taskManager.add(data: data) {
          baseContext = SVGParser.parse(data: data)
          setNeedsDisplay()
        }
      }
    }
  }

  override public var contentMode: UIView.ContentMode {
    didSet {
      if contentMode != oldValue {
        setNeedsDisplay()
      }
    }
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    // Otherwise UIKit only scales the image rendered for the old size, margins and all.
    if bounds.size != renderedSize {
      setNeedsDisplay()
    }
  }

  // UIKit marks the layer for display only for a view that implements `draw(_:)`. This view renders in
  // `display(_:)` instead, so it marks the layer itself.
  override public func setNeedsDisplay() {
    super.setNeedsDisplay()
    layer.setNeedsDisplay()
  }

  override public func setNeedsDisplay(_ rect: CGRect) {
    super.setNeedsDisplay(rect)
    layer.setNeedsDisplay()
  }

  /// Starts rendering the document for the layer's display.
  ///
  /// The view renders in the background and keeps showing its current image until the new one is ready,
  /// so that it does not blink. Implementing `draw(_:)` instead would make UIKit replace the image with an
  /// empty one before drawing.
  override public func display(_: CALayer) {
    let rect = bounds
    renderedSize = rect.size
    let generation = nextRenderingGeneration()
    let scale = UIScreen.main.scale
    let capturedBase = baseContext
    let capturedMode = contentMode
    let timeoutDuration = configuration.timeoutDuration
    taskManager.startTask(
      priority: configuration.taskPriority,
      operation: { [weak self] in
        let result = await SVGUIView.makeImage(
          rect: rect, scale: scale, base: capturedBase,
          contentMode: capturedMode, timeoutDuration: timeoutDuration
        )
        await MainActor.run {
          self?.show(result, ofRendering: generation)
          self?.startRendering()
        }
      })
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

  private nonisolated static func getTransform(
    viewBox: CGRect, size: CGSize, contentMode: UIView.ContentMode
  ) -> CGAffineTransform {
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

  private func startRendering() {
    let displayLink = CADisplayLink(
      target: self,
      selector: #selector(updateContents)
    )
    displayLink.add(to: .main, forMode: .common)
  }

  @objc
  private func updateContents(_ displayLink: CADisplayLink) {
    Task {
      if let data = await taskManager.takeData() {
        let newBase = SVGParser.parse(data: data)
        baseContext = newBase
        let scale = UIScreen.main.scale
        let capturedMode = contentMode
        let capturedFrame = frame
        let timeoutDuration = configuration.timeoutDuration
        renderedSize = capturedFrame.size
        let generation = nextRenderingGeneration()
        let result = await SVGUIView.makeImage(
          rect: capturedFrame, scale: scale, base: newBase,
          contentMode: capturedMode, timeoutDuration: timeoutDuration
        )
        show(result, ofRendering: generation)
      } else {
        displayLink.invalidate()
        await taskManager.finishTask()
      }
    }
  }

  /// Counts a rendering that starts, and returns the number to pass to `show(_:ofRendering:)`.
  private func nextRenderingGeneration() -> Int {
    renderingGeneration += 1
    return renderingGeneration
  }

  /// Shows the result of a rendering, unless a newer rendering has started since, so that a rendering
  /// for an old size or old data does not replace a newer image.
  private func show(_ result: Result<CGImage, SVGRenderingError>, ofRendering generation: Int) {
    guard generation == renderingGeneration else { return }
    show(result)
  }

  /// Shows the result of a rendering.
  ///
  /// A rendering that timed out keeps the image that the view shows, so that a slow rendering does not
  /// blank the view.
  func show(_ result: Result<CGImage, SVGRenderingError>) {
    switch result {
    case .success(let image):
      layer.contents = image
    case .failure(.missingRootElement), .failure(.zeroSizedRect):
      layer.contents = nil
    case .failure(.timedOut):
      Self.logger.warning("Rendering took longer than the timeout and was cancelled. The view keeps its current image.")
    }
  }

  /// Renders the current SVG document into an image.
  ///
  /// The image is rendered at the main screen's scale with the view's current
  /// `contentMode`. The view's displayed contents do not change.
  ///
  /// - Parameter rect: The rectangle to render into. Pass `nil` to use the
  ///   view's frame.
  /// - Returns: The rendered image.
  /// - Throws: ``SVGRenderingError/missingRootElement`` if the document has no
  ///   root `svg` element, ``SVGRenderingError/zeroSizedRect`` if the rectangle
  ///   has no width or no height, or ``SVGRenderingError/timedOut`` if rendering
  ///   takes longer than ``SVGUIViewConfiguration/timeoutDuration``.
  public func takeSnapshot(rect: CGRect? = nil) async throws(SVGRenderingError) -> UIImage {
    let rect = rect ?? frame
    let scale = UIScreen.main.scale
    let capturedBase = baseContext
    let capturedMode = contentMode
    let timeoutDuration = configuration.timeoutDuration
    let image = try await SVGUIView.makeImage(
      rect: rect, scale: scale, base: capturedBase,
      contentMode: capturedMode, timeoutDuration: timeoutDuration
    ).get()
    return UIImage(cgImage: image)
  }

  @concurrent
  private static func makeImage(
    rect: CGRect,
    scale: CGFloat,
    base: SVGBaseContext,
    contentMode: UIView.ContentMode,
    timeoutDuration: Duration
  ) async -> Result<CGImage, SVGRenderingError> {
    guard let svg = base.root else { return .failure(.missingRootElement) }
    let viewBox = svg.getViewBox(size: rect.size)

    let frameWidth = Int((rect.width * scale).rounded(.up))
    let frameHeight = Int((rect.height * scale).rounded(.up))
    // `CGContext` cannot make a bitmap without a pixel.
    guard frameWidth > 0, frameHeight > 0 else { return .failure(.zeroSizedRect) }
    let bytesPerRow = 4 * frameWidth

    let graphics = CGContext(
      data: nil,
      width: frameWidth,
      height: frameHeight,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | kCGBitmapByteOrder32Host.rawValue)!
    graphics.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, CGFloat(frameHeight)))

    let context = SVGContext(
      base: base,
      graphics: graphics,
      viewPort: rect,
      scale: scale
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

    let transform = getTransform(viewBox: viewBox, size: rect.size, contentMode: contentMode)
    context.concatenate(transform)
    switch contentMode {
    case .scaleAspectFill, .scaleAspectFit, .scaleToFill:
      let scale = viewBox.width / width
      context.concatenate(CGAffineTransform(scaleX: scale, y: scale))
    default:
      break
    }
    let drawTask = Task<CGImage?, Never> {
      await svg.draw(context, mode: .root)
      context.popViewBox()
      context.restoreGState()
      guard !Task.isCancelled else {
        return nil
      }
      return graphics.makeImage()
    }

    let timeoutTask = Task {
      try? await Task.sleep(for: timeoutDuration)
      drawTask.cancel()
    }
    let value = await drawTask.value
    timeoutTask.cancel()
    // Only the timeout task cancels `drawTask`, and `makeImage()` of a bitmap context returns an image
    // otherwise, so `nil` means that rendering timed out.
    guard let value else { return .failure(.timedOut) }
    return .success(value)
  }
}

private actor TaskManager {
  enum Status {
    case busy
    case available
  }

  private(set) var status: Status = .available
  private var dataQueue: [Data]
  init() {
    dataQueue = []
  }

  nonisolated func startTask(priority: TaskPriority, operation: @escaping @Sendable () async -> Void) {
    Task.detached(priority: priority) { [weak self] in
      await self?.setBusy()
      await operation()
    }
  }

  private func setBusy() {
    status = .busy
  }

  func finishTask() {
    status = .available
  }

  func add(data: Data) -> Bool {
    switch status {
    case .busy:
      dataQueue.append(data)
      return true
    case .available:
      return false
    }
  }

  func takeData() -> Data? {
    guard !dataQueue.isEmpty else { return nil }
    return dataQueue.removeFirst()
  }
}
