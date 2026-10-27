import SVGCore
import SVGRenderCG
import SVGRenderLayer
public import UIKit
import os

/// A view that displays a single SVG image.
///
/// The view parses SVG data and renders it in a background task. Assign new data
/// to ``data`` to change the displayed image. The view renders again when its
/// size or its `contentMode` changes, and a new rendering stops the one in
/// progress. Releasing the view stops its rendering too.
///
/// With a ``SVGUIViewConfiguration/animation`` other than
/// ``SVGUIViewConfiguration/AnimationMode/none``, the view plays the animations
/// of its document, and ``play()``, ``pause()`` and ``seek(to:)`` control
/// them. The animations don't advance while the view isn't in a window, is
/// hidden or has no size, or while the app is in the background. While it can
/// play animations, the view shows its document in layers of its layer,
/// instead of in one image.
public class SVGUIView: UIView {
  private var baseContext: SVGBaseContext {
    didSet {
      animationEnd = baseContext.animationEnd()
      promoted = baseContext.elementsWithAnimatedCompositing()
    }
  }
  /// The elements whose transform or opacity can change, which get layers of their own.
  private var promoted: Set<ElementID>
  /// The time in seconds after which the document doesn't change, where the animations stop advancing, which is
  /// infinite for animations that don't end.
  private var animationEnd: Double
  /// The rendering in progress, which a new rendering and the release of the view cancel.
  private(set) var renderingTask: Task<Void, Never>?
  /// The settings that control background rendering and the animations.
  ///
  /// Changing the ``SVGUIViewConfiguration/animation`` mode plays or pauses
  /// the animations. Changing it to ``SVGUIViewConfiguration/AnimationMode/none``
  /// also moves them back to time zero.
  public var configuration: SVGUIViewConfiguration = .init() {
    didSet {
      // A view that can play animations shows them in layers, so it renders again when it starts or stops.
      if (configuration.animation == .none) != (oldValue.animation == .none) {
        setNeedsDisplay()
      }
      if configuration.animation != oldValue.animation {
        switch configuration.animation {
        case .none:
          isPlaying = false
          currentTime = .zero
        case .play:
          isPlaying = true
        case .paused:
          isPlaying = false
        }
      }
      updatePlayback()
    }
  }
  static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")
  /// The size that the view last rendered at, so that it renders again when its size changes.
  private var renderedSize: CGSize?
  /// Counts the renderings that the view starts, so that one that finishes after a newer one is not shown.
  private var renderingGeneration = 0
  /// Whether the latest rendering hasn't finished yet.
  private var isRendering = false
  /// Whether a frame of the animations waits for the rendering in progress, which shows the latest time when it
  /// starts, so that frames that come while rendering is slower are skipped.
  private var needsFrame = false
  /// The time of the animations that the latest rendering shows.
  private var renderedTime: Duration?
  /// The layer that shows the layers of the document while the view can play animations.
  private let layerTreeHost: CALayer = {
    let layer = CALayer()
    layer.anchorPoint = .zero
    return layer
  }()
  /// The layers in the host.
  private lazy var layerTree = LayerTree(host: layerTreeHost)

  /// The time of the animations.
  ///
  /// The time starts at zero when the document is loaded, and advances while
  /// the view plays its animations. Assigning new ``data`` moves it back to
  /// zero.
  public private(set) var currentTime: Duration = .zero
  /// Whether the animations advance when the view can be seen, which ``play()`` and ``pause()`` change.
  private var isPlaying = false
  /// Whether the app is in the background, where the animations don't advance.
  private var isInBackground = false
  /// The clock that advances the animations, which tests replace.
  var clock: any AnimationClock = DisplayLinkClock() {
    didSet {
      oldValue.isRunning = false
      oldValue.onFrame = nil
      startObservingClock()
      updatePlayback()
    }
  }
  /// Whether Reduce Motion is on, which tests replace.
  var isReduceMotionEnabled: () -> Bool = { UIAccessibility.isReduceMotionEnabled } {
    didSet { updatePlayback() }
  }

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
    animationEnd = baseContext.animationEnd()
    promoted = baseContext.elementsWithAnimatedCompositing()
    super.init(frame: frame)
    backgroundColor = .clear
    startObservingClock()
    observeNotifications()
    setNeedsDisplay()
  }

  /// Creates a view with the given frame that displays the given SVG data.
  ///
  /// - Parameters:
  ///   - frame: The frame rectangle for the view.
  ///   - data: The SVG data to display. Pass `nil` to create an empty view.
  public convenience init(frame: CGRect, data: Data? = nil) {
    let data = data ?? Data()
    let baseContext = Self.parse(data)
    self.init(frame: frame, baseContext: baseContext, data: data)
  }

  /// Creates a view that displays the given SVG data.
  ///
  /// The view's frame is sized to the SVG document's `width` and `height`.
  ///
  /// - Parameter data: The SVG data to display.
  public convenience init(data: Data = Data()) {
    let baseContext = Self.parse(data)
    let size = baseContext.root?.size ?? .zero
    self.init(frame: .init(origin: .zero, size: size), baseContext: baseContext, data: data)
  }

  /// Parses SVG data, with the fonts of text styles that only UIKit provides.
  private static func parse(_ data: Data) -> SVGBaseContext {
    _ = installTextStyleFonts
    return SVGParser.parse(data: data)
  }

  /// The SVG data that the view displays.
  ///
  /// Setting this property parses the new data and redraws the view
  /// asynchronously. A rendering in progress stops, so that the view renders
  /// only the latest data. Setting the data that the view already displays
  /// does nothing.
  public var data: Data {
    didSet {
      // SVGView sets its data on every update of the SwiftUI view.
      guard data != oldValue else { return }
      baseContext = Self.parse(data)
      currentTime = .zero
      updatePlayback()
      setNeedsDisplay()
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
    updatePlayback()
  }

  override public func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlayback()
  }

  override public var isHidden: Bool {
    didSet { updatePlayback() }
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

  /// Starts rendering the document for the layer's display, and stops the rendering in progress.
  ///
  /// The view renders in the background and keeps showing its current image until the new one is ready,
  /// so that it does not blink. Implementing `draw(_:)` instead would make UIKit replace the image with an
  /// empty one before drawing.
  override public func display(_: CALayer) {
    renderingTask?.cancel()
    needsFrame = false
    startRendering()
  }

  /// Starts rendering the document at the time that the view displays.
  private func startRendering() {
    let rect = bounds
    renderedSize = rect.size
    let generation = nextRenderingGeneration()
    let scale = UIScreen.main.scale
    let capturedBase = baseContext
    let time = displayedTime
    renderedTime = time
    let fit = ContentFit(contentMode)
    let timeoutDuration = configuration.timeoutDuration
    let promoted = configuration.animation == .none ? nil : promoted
    isRendering = true
    renderingTask = Task(priority: configuration.taskPriority) { [weak self] in
      if let promoted {
        let result = await SVGUIView.makeLayers(
          rect: rect, scale: scale, base: capturedBase, promoted: promoted, time: time, fit: fit,
          timeoutDuration: timeoutDuration)
        self?.finishRendering(ofRendering: generation) { $0.showLayers(result) }
      } else {
        let result = await SVGUIView.makeImage(
          rect: rect, scale: scale, base: capturedBase, time: time,
          fit: fit, timeoutDuration: timeoutDuration
        )
        self?.finishRendering(ofRendering: generation) { $0.show(result) }
      }
    }
  }

  /// Shows the result of a rendering, unless a newer rendering has started since, and starts the frame that waits
  /// for it. A rendering for an old size or old data that finished before it was cancelled doesn't replace a newer
  /// image.
  private func finishRendering(ofRendering generation: Int, show: (SVGUIView) -> Void) {
    guard generation == renderingGeneration else { return }
    isRendering = false
    show(self)
    if needsFrame {
      needsFrame = false
      startRendering()
    }
  }

  /// Renders the frame at the time that the view displays, after the rendering in progress if there is one.
  ///
  /// A frame doesn't stop the rendering in progress, unlike a new size or new data, so that the view shows
  /// frames even when rendering one takes longer than the display shows it.
  private func renderFrame() {
    if isRendering {
      needsFrame = true
    } else {
      startRendering()
    }
  }

  deinit {
    // The rendering holds the view weakly, so without this it would go on until the timeout.
    renderingTask?.cancel()
  }

  /// Plays the animations of the document from the current time.
  ///
  /// This does nothing when the configuration's
  /// ``SVGUIViewConfiguration/animation`` is
  /// ``SVGUIViewConfiguration/AnimationMode/none``.
  public func play() {
    guard configuration.animation != .none else { return }
    isPlaying = true
    updatePlayback()
  }

  /// Holds the animations of the document at the current time.
  public func pause() {
    isPlaying = false
    updatePlayback()
  }

  /// Moves the animations of the document to a time, and displays it.
  ///
  /// This does nothing when the configuration's
  /// ``SVGUIViewConfiguration/animation`` is
  /// ``SVGUIViewConfiguration/AnimationMode/none``.
  ///
  /// - Parameter time: The time to move to. A negative time moves to zero.
  public func seek(to time: Duration) {
    guard configuration.animation != .none else { return }
    currentTime = max(time, .zero)
    updatePlayback()
  }

  /// Whether Reduce Motion holds the animations at time zero.
  private var isHeldByReduceMotion: Bool {
    configuration.animation != .none && !configuration.playsWithReduceMotion && isReduceMotionEnabled()
  }

  /// The time of the animations that the view displays.
  private var displayedTime: Duration {
    configuration.animation == .none || isHeldByReduceMotion ? .zero : currentTime
  }

  /// Whether the animations advance: they play, they haven't ended, and the view can be seen.
  private var advances: Bool {
    configuration.animation != .none && isPlaying && currentTime.seconds < animationEnd && !isHeldByReduceMotion
      && window != nil && !isHidden && bounds.width > 0 && bounds.height > 0 && !isInBackground
  }

  /// Starts or stops the clock, and renders the displayed time if it changed.
  private func updatePlayback() {
    clock.isRunning = advances
    if let renderedTime, renderedTime != displayedTime {
      renderFrame()
    }
  }

  private func startObservingClock() {
    clock.onFrame = { [weak self] elapsed in
      guard let self else { return }
      currentTime += elapsed
      renderFrame()
      // The clock stops after the frame that passes the end of the animations.
      updatePlayback()
    }
  }

  /// Observes the app moving to the background and back, and changes of Reduce Motion. The notification center
  /// stops sending notifications to the view when it's released.
  private func observeNotifications() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(reduceMotionStatusDidChange),
      name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
  }

  @objc private func didEnterBackground() {
    isInBackground = true
    updatePlayback()
  }

  @objc private func willEnterForeground() {
    isInBackground = false
    updatePlayback()
  }

  @objc private func reduceMotionStatusDidChange() {
    updatePlayback()
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

  /// Counts a rendering that starts, and returns the number to pass to `finishRendering(ofRendering:show:)`.
  private func nextRenderingGeneration() -> Int {
    renderingGeneration += 1
    return renderingGeneration
  }

  /// Shows the result of a rendering.
  ///
  /// A rendering that timed out or couldn't allocate its image keeps the image that the view shows, so that a
  /// slow rendering or a temporary shortage of memory does not blank the view.
  func show(_ result: Result<CGImage, SVGRenderingError>) {
    switch result {
    case .success(let image):
      layerTreeHost.removeFromSuperlayer()
      layerTree.clear()
      layer.contents = image
    case .failure(let error):
      show(error)
    }
  }

  /// Shows the result of a rendering into layers, in the layer that hosts them.
  func showLayers(_ result: Result<RenderedContainer, SVGRenderingError>) {
    switch result {
    case .success(let layers):
      layer.contents = nil
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      if layerTreeHost.superlayer !== layer {
        layer.addSublayer(layerTreeHost)
      }
      layerTreeHost.bounds = layer.bounds
      layerTreeHost.position = layer.bounds.origin
      CATransaction.commit()
      layerTree.show(layers)
    case .failure(let error):
      show(error)
    }
  }

  /// Shows that a rendering failed. A rendering that timed out or couldn't allocate its image keeps what the view
  /// shows.
  private func show(_ error: SVGRenderingError) {
    switch error {
    case .missingRootElement, .zeroSizedRect:
      layer.contents = nil
      layerTree.clear()
    case .cancelled:
      // A newer rendering cancels the one before it, so this is not worth a warning.
      break
    case .timedOut:
      Self.logger.warning("Rendering took longer than the timeout and was cancelled. The view keeps its current image.")
    case .allocationFailed:
      Self.logger.warning("The memory for the image to render into couldn't be allocated. The view keeps its current image.")
    }
  }

  /// Renders the current SVG document into an image, as it is at a time of its
  /// animations.
  ///
  /// The image is rendered at the main screen's scale with the view's current
  /// `contentMode`. The view's displayed contents do not change.
  ///
  /// The time starts at zero when the document is loaded, which is the time
  /// that the view displays. A document without animations looks the same at
  /// any time.
  ///
  /// - Parameters:
  ///   - rect: The rectangle to render into. Pass `nil` to use the view's
  ///     frame.
  ///   - time: The time of the document's animations.
  /// - Returns: The rendered image.
  /// - Throws: ``SVGRenderingError/missingRootElement`` if the document has no
  ///   root `svg` element, ``SVGRenderingError/zeroSizedRect`` if the rectangle
  ///   has no width or no height, ``SVGRenderingError/timedOut`` if rendering
  ///   takes longer than ``SVGUIViewConfiguration/timeoutDuration``, or
  ///   ``SVGRenderingError/cancelled`` if the task that calls this method is
  ///   cancelled before rendering finishes, or
  ///   ``SVGRenderingError/allocationFailed`` if the memory for the image
  ///   couldn't be allocated.
  public func takeSnapshot(
    rect: CGRect? = nil, at time: Duration = .zero
  ) async throws(SVGRenderingError) -> UIImage {
    let rect = rect ?? frame
    let scale = UIScreen.main.scale
    let capturedBase = baseContext
    let fit = ContentFit(contentMode)
    let timeoutDuration = configuration.timeoutDuration
    let image = try await SVGUIView.makeImage(
      rect: rect, scale: scale, base: capturedBase, time: time,
      fit: fit, timeoutDuration: timeoutDuration
    ).get()
    return UIImage(cgImage: image)
  }

  @concurrent
  private static func makeImage(
    rect: CGRect,
    scale: CGFloat,
    base: SVGBaseContext,
    time: Duration,
    fit: ContentFit,
    timeoutDuration: Duration
  ) async -> Result<CGImage, SVGRenderingError> {
    guard base.root != nil else { return .failure(.missingRootElement) }

    // `CGContext` cannot make a bitmap without a pixel.
    guard (rect.width * scale).rounded(.up) > 0, (rect.height * scale).rounded(.up) > 0 else {
      return .failure(.zeroSizedRect)
    }
    guard let graphics = CGContext.bitmap(size: rect.size, scale: scale, space: CGColorSpaceCreateDeviceRGB()) else {
      return .failure(.allocationFailed)
    }
    graphics.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, CGFloat(graphics.height)))

    return await withRenderingTimeout(timeoutDuration) {
      // The computed values at the time are computed in the task, so that the timeout stops them too.
      let builder = RenderTreeBuilder(base: base.at(time: time.seconds), viewPort: rect, scale: scale)
      guard let tree = await builder.build(fit: fit) else { return nil }
      await CGPainter(scale: scale).paint(tree, into: graphics)
      guard !Task.isCancelled else {
        return nil
      }
      return graphics.makeImage()
    }
  }

  /// Renders the document at a time into layers: the layers of the elements whose transform or opacity changes, and
  /// the contents of the layers between them.
  @concurrent
  private static func makeLayers(
    rect: CGRect,
    scale: CGFloat,
    base: SVGBaseContext,
    promoted: Set<ElementID>,
    time: Duration,
    fit: ContentFit,
    timeoutDuration: Duration
  ) async -> Result<RenderedContainer, SVGRenderingError> {
    guard base.root != nil else { return .failure(.missingRootElement) }
    guard (rect.width * scale).rounded(.up) > 0, (rect.height * scale).rounded(.up) > 0 else {
      return .failure(.zeroSizedRect)
    }
    return await withRenderingTimeout(timeoutDuration) {
      let builder = RenderTreeBuilder(base: base.at(time: time.seconds), viewPort: rect, scale: scale)
      guard let tree = await builder.build(fit: fit) else { return nil }
      return await LayerPlanner(promoted: promoted, scale: scale).plan(tree, in: rect).painted(scale: scale)
    }
  }
}

extension Duration {
  /// The duration in seconds.
  var seconds: Double {
    let (seconds, attoseconds) = components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  /// The duration as a dispatch time interval, which counts whole nanoseconds.
  var dispatchTimeInterval: DispatchTimeInterval {
    let (seconds, attoseconds) = components
    let (nanoseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
    return overflow ? .never : .nanoseconds(Int(nanoseconds + attoseconds / 1_000_000_000))
  }
}

extension ContentFit {
  /// How the view fits its document in its bounds with a content mode.
  init(_ contentMode: UIView.ContentMode) {
    switch contentMode {
    case .scaleToFill:
      self.init(preserveAspectRatio: .none, stretches: true, scales: true)
    case .scaleAspectFit:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
    case .scaleAspectFill:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .slice), stretches: false, scales: true)
    case .redraw:
      self.init(preserveAspectRatio: .none, stretches: false, scales: false)
    case .center:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .mid, yAlign: .mid))
    case .top:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .mid, yAlign: .min))
    case .bottom:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .mid, yAlign: .max))
    case .left:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .min, yAlign: .mid))
    case .right:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .max, yAlign: .mid))
    case .topLeft:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .min, yAlign: .min))
    case .topRight:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .max, yAlign: .min))
    case .bottomLeft:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .min, yAlign: .max))
    case .bottomRight:
      self.init(alignedTo: PreserveAspectRatio(xAlign: .max, yAlign: .max))
    @unknown default:
      self.init(preserveAspectRatio: .none, stretches: false, scales: false)
    }
  }

  private init(alignedTo preserveAspectRatio: PreserveAspectRatio) {
    self.init(preserveAspectRatio: preserveAspectRatio, stretches: false, scales: false)
  }
}
