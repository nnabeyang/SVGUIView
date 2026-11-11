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
/// hidden or has no size, or while the app is in the background, and they stop
/// after the time at which the document doesn't change any more. While its
/// animations play, the view shows its document in layers of its layer,
/// instead of in one image. While they don't, such as when they're paused or
/// have ended, it shows the image that ``takeSnapshot(rect:at:scale:)`` renders for
/// the time.
public class SVGUIView: UIView {
  /// The context of the document, with the values that the view finds in it.
  private var loaded: LoadedDocument {
    didSet {
      // The values of another context aren't compared with the frame that the view shows.
      shownStyled = nil
    }
  }
  private var baseContext: SVGBaseContext {
    get { loaded.context }
    set { loaded = LoadedDocument(context: newValue) }
  }
  /// The document that the view displays, which an app reads and changes.
  ///
  /// The view shows the changes at its next rendering. Assigning new ``data``
  /// replaces the document.
  public private(set) var document: SVGDocument {
    didSet {
      oldValue.host = nil
      document.host = self
      // The animations of the document that the view no longer shows don't finish.
      resumeWaiters { _ in true }
    }
  }
  /// The elements whose transform or opacity can change, which get layers of their own.
  private var promoted: Set<ElementID> { loaded.promoted }
  /// The elements whose painting changes in other ways, which tells the layers that frames paint again.
  private var painting: Set<ElementID> { loaded.painting }
  /// The CSS animations whose ends tasks wait for, which ``SVGDocument/Animation/finished()`` adds, with the tokens
  /// that the cancellations of the tasks find them by.
  private(set) var finishWaiters = [(token: Int, id: CSSAnimationID, continuation: CheckedContinuation<Void, Never>)]()
  /// The token of the next task that waits for a CSS animation.
  private var nextFinishWaiterToken = 0
  /// Whether the changes of the document are applied soon for the tasks that wait for the CSS animations.
  private var appliesChangesForWaiters = false
  /// The time in seconds after which the document doesn't change, where the animations stop advancing, which is
  /// infinite for animations that don't end.
  private var animationEnd: Double { loaded.animationEnd }
  /// Counts the data that the view loads, so that the data that ``setData(_:)`` parses isn't shown if newer data was
  /// given meanwhile.
  private var loadGeneration = 0
  /// The rendering in progress, which a new rendering and the release of the view cancel.
  private(set) var renderingTask: Task<Void, Never>?
  /// The settings that control background rendering and the animations.
  ///
  /// Changing the ``SVGUIViewConfiguration/animation`` mode plays or pauses
  /// the animations. Changing it to ``SVGUIViewConfiguration/AnimationMode/none``
  /// also moves them back to time zero.
  public var configuration: SVGUIViewConfiguration = .init() {
    didSet {
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
      if configuration.externalResources != oldValue.externalResources {
        // The style sheets in other files are read again from the files that the view reads now.
        if baseContext.hasExternalStyleSheets {
          baseContext = baseContext.unresolvingExternalStyleSheets(at: displayedTime.seconds)
        }
        setNeedsDisplay()
      }
      updatePlayback()
    }
  }
  static let logger = Logger(subsystem: "com.github.nnabeyang.SVGUIView", category: "main")
  /// Records each rendering as a "Render" interval, and each frame that a slower rendering skips as a "Skipped frame"
  /// event, which Instruments and the metrics of XCTest measure. A rendering into layers records its stages as
  /// "Style", "Build", "Plan" and "Paint" intervals in it.
  nonisolated static let signposter = OSSignposter(subsystem: "com.github.nnabeyang.SVGUIView", category: "Rendering")
  /// The size that the view last rendered at, so that it renders again when its size changes.
  private var renderedSize: CGSize?
  /// Counts the renderings that the view starts, so that one that finishes after a newer one is not shown.
  private(set) var renderingGeneration = 0
  /// Whether the latest rendering hasn't finished yet.
  private(set) var isRendering = false
  /// Whether a frame of the animations waits for the rendering in progress, which shows the latest time when it
  /// starts, so that frames that come while rendering is slower are skipped.
  private var needsFrame = false
  /// The time of the animations that the latest rendering shows.
  private var renderedTime: Duration?
  /// Whether the latest rendering that started renders into layers, or `nil` before the first one.
  private var renderedInLayers: Bool?
  /// The layer that shows the layers of the document while the view can play animations.
  private let layerTreeHost: CALayer = {
    let layer = CALayer()
    layer.anchorPoint = .zero
    return layer
  }()
  /// The layers in the host, which the frames reuse.
  private lazy var layerTree = LayerTree(host: layerTreeHost)
  /// The layers that the view shows, whose contents the next frame shows where they don't change.
  private var shownLayers: RenderedContainer?
  /// The render nodes of the elements that make the same nodes at every time, of the frame that the view shows,
  /// which the next frame reuses.
  private var shownNodes = RenderNodeCache()
  /// The document at the time of the frame that the view shows, which the next frame compares its animated values
  /// with, so that it isn't rendered if they're the same.
  private var shownStyled: SVGBaseContext?
  /// Counts the frames that weren't rendered since their animated values were the same as the frame before.
  private(set) var unchangedFrameCount = 0

  /// The time of the animations.
  ///
  /// The time starts at zero when the document is loaded, and advances while
  /// the view plays its animations. Assigning new ``data`` moves it back to
  /// zero.
  public private(set) var currentTime: Duration = .zero
  /// Whether the animations advance when the view can be seen, which ``play()`` and ``pause()`` change.
  private var isPlaying = false
  /// Whether the app is in the background, where the animations don't advance, and the GPU can't be used.
  private var isInBackground = false
  /// Whether the layers run the filters of the elements that are painted into layers of their own on the GPU, where it
  /// gives the same results as the CPU, which tests turn off to compare them.
  var runsFiltersOnGPU = true
  /// Whether every element with a filter is painted into a layer of its own, as if what it paints changed, which
  /// tests turn on to run all the filters of a document on the GPU.
  var paintsFiltersIntoOwnLayers = false
  /// Whether the view shows its document in layers while its animations don't play too, which tests and benchmarks
  /// turn on to render frames of a view that holds its animations in layers.
  var showsStillFramesInLayers = false
  /// How many layers that the view shows ran their filters on the GPU.
  var layersFilteredOnGPU: Int {
    shownLayers?.paintedContents.count(where: \.filteredOnGPU) ?? 0
  }
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
  /// The URL becomes the view's ``baseURL``, so that the document reads the
  /// files that it refers to, such as the images beside it, as the
  /// configuration's ``SVGUIViewConfiguration/externalResources`` allows.
  ///
  /// - Parameter url: The URL of an SVG file. The file is read synchronously.
  /// - Returns: `nil` if the file cannot be read.
  public convenience init?(contentsOf url: URL) {
    guard let data = try? Data(contentsOf: url) else { return nil }
    self.init(data: data, baseURL: url)
  }

  init(frame: CGRect, baseContext: SVGBaseContext, data: Data = Data(), baseURL: URL? = nil) {
    storedData = data
    self.baseURL = baseURL
    loaded = LoadedDocument(context: baseContext)
    document = SVGDocument(tree: baseContext.document)
    super.init(frame: frame)
    // The default configuration plays the animations, which a change of the configuration doesn't start.
    isPlaying = configuration.animation == .play
    backgroundColor = .clear
    startObservingClock()
    observeNotifications()
    // A screen of another gamut shows colors outside sRGB in another way, and one of another scale has other pixels.
    registerForTraitChanges([UITraitDisplayGamut.self, UITraitDisplayScale.self]) { (view: SVGUIView, _) in
      view.setNeedsDisplay()
    }
    document.host = self
    setNeedsDisplay()
  }

  /// Creates a view with the given frame that displays the given SVG data.
  ///
  /// - Parameters:
  ///   - frame: The frame rectangle for the view.
  ///   - data: The SVG data to display. Pass `nil` to create an empty view.
  ///   - baseURL: The URL that the document's relative URLs are relative to,
  ///     which is usually the URL of the file that the data was read from, or
  ///     `nil` if the document reads no other files.
  public convenience init(frame: CGRect, data: Data? = nil, baseURL: URL? = nil) {
    let data = data ?? Data()
    let baseContext = Self.parse(data)
    self.init(frame: frame, baseContext: baseContext, data: data, baseURL: baseURL)
  }

  /// Creates a view that displays the given SVG data.
  ///
  /// The view's frame is sized to the SVG document's `width` and `height`.
  ///
  /// - Parameter data: The SVG data to display.
  public convenience init(data: Data = Data()) {
    self.init(data: data, baseURL: nil)
  }

  /// Creates a view that displays the given SVG data, which refers to other
  /// files relative to a URL.
  ///
  /// The view's frame is sized to the SVG document's `width` and `height`.
  ///
  /// - Parameters:
  ///   - data: The SVG data to display.
  ///   - baseURL: The URL that the document's relative URLs are relative to,
  ///     which is usually the URL of the file that the data was read from, or
  ///     `nil` if the document reads no other files.
  public convenience init(data: Data, baseURL: URL?) {
    let baseContext = Self.parse(data)
    let size = baseContext.root?.size ?? .zero
    self.init(frame: .init(origin: .zero, size: size), baseContext: baseContext, data: data, baseURL: baseURL)
  }

  /// Parses SVG data, with the fonts of text styles that only UIKit provides.
  private static func parse(_ data: Data) -> SVGBaseContext {
    _ = installTextStyleFonts
    return SVGParser.parse(data: data)
  }

  /// Parses SVG data off the main actor, with the values that the view finds in the document. The fonts of text
  /// styles are installed on the main actor before.
  @concurrent
  nonisolated private static func load(_ data: Data) async -> LoadedDocument {
    await parseObserver?()
    return LoadedDocument(context: SVGParser.parse(data: data))
  }

  /// Called off the main actor where ``setData(_:)`` parses its data, which tests check, and hold to give other data
  /// meanwhile.
  @TaskLocal nonisolated static var parseObserver: (@Sendable () async -> Void)?

  /// The SVG data that the view displays.
  private var storedData: Data

  /// The URL that the relative URLs of the document are relative to, or
  /// `nil` if the document reads no other files.
  ///
  /// It's the URL that ``init(contentsOf:)`` reads the document from, or the
  /// one given with the data to ``init(data:baseURL:)`` or
  /// ``setData(_:baseURL:)``. Setting ``data`` sets it to `nil`. The
  /// configuration's ``SVGUIViewConfiguration/externalResources`` decides which
  /// of the files that the document refers to the view reads.
  public private(set) var baseURL: URL?
  /// The data of the files that the document has read, which the renderings of the document share.
  private var resourceCache = ExternalResourceCache()
  /// Counts the documents that the view shows, so that the style sheets that a rendering read for a document aren't
  /// given to another one.
  private var documentGeneration = 0
  /// Reads the files for the renderings that start in a task instead of the file system, which tests use to hold
  /// reading.
  @TaskLocal nonisolated static var resourceFetch: ExternalResourceLoader.Fetch?

  /// The SVG data that the view displays.
  ///
  /// Setting this property parses the new data on the main actor, which takes
  /// longer for a larger document, and redraws the view asynchronously. A
  /// rendering in progress stops, so that the view renders only the latest
  /// data. The new data also replaces ``document`` at once. Setting the data
  /// that the view already displays does nothing.
  ///
  /// The data has no ``baseURL``, so the document reads no other files. To
  /// give the data with a base URL, use ``setData(_:baseURL:)``. To parse a
  /// larger document without blocking the main actor, use ``setData(_:)``.
  public var data: Data {
    get { storedData }
    set {
      // A newer data replaces the data that `setData(_:)` is parsing.
      loadGeneration += 1
      // SVGView sets its data on every update of the SwiftUI view.
      guard newValue != storedData || baseURL != nil else { return }
      show(newValue, baseURL: nil, loaded: LoadedDocument(context: Self.parse(newValue)))
    }
  }

  /// Parses SVG data off the main actor and shows it.
  ///
  /// The view keeps showing its current document while the data is parsed,
  /// and then replaces ``data`` and ``document`` and redraws, as setting
  /// ``data`` does. Parsing a larger document this way doesn't block the main
  /// actor, which setting ``data`` does.
  ///
  /// If newer data is given to the view before the parsing ends, by this
  /// method or by setting ``data``, or if the task is canceled, the parsed data
  /// isn't shown. Giving the data that the view already displays does nothing.
  ///
  /// ```swift
  /// Task {
  ///     let data = try await loadData()
  ///     await svgView.setData(data)
  /// }
  /// ```
  ///
  /// - Parameter data: The SVG data to display.
  public func setData(_ data: Data) async {
    await setData(data, baseURL: nil)
  }

  /// Parses SVG data off the main actor and shows it, with the URL that its
  /// relative URLs are relative to.
  ///
  /// It parses and shows the data as ``setData(_:)`` does, and sets
  /// ``baseURL`` when it shows it. Giving the data and the base URL that the
  /// view already displays does nothing.
  ///
  /// - Parameters:
  ///   - data: The SVG data to display.
  ///   - baseURL: The URL that the document's relative URLs are relative to,
  ///     which is usually the URL of the file that the data was read from, or
  ///     `nil` if the document reads no other files.
  public func setData(_ data: Data, baseURL: URL?) async {
    loadGeneration += 1
    let generation = loadGeneration
    guard data != storedData || baseURL != self.baseURL else { return }
    _ = Self.installTextStyleFonts
    let loaded = await Self.load(data)
    guard generation == loadGeneration, !Task.isCancelled else { return }
    show(data, baseURL: baseURL, loaded: loaded)
  }

  /// Shows new data with its document at time zero.
  private func show(_ data: Data, baseURL: URL?, loaded: LoadedDocument) {
    documentGeneration += 1
    storedData = data
    self.baseURL = baseURL
    // The files that another document refers to by the same URLs can be other files.
    resourceCache = ExternalResourceCache()
    self.loaded = loaded
    document = SVGDocument(tree: loaded.context.document)
    currentTime = .zero
    updatePlayback()
    setNeedsDisplay()
    // The size of the document can be another one.
    invalidateIntrinsicContentSize()
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
    applyDocumentChanges()
    renderingTask?.cancel()
    needsFrame = false
    startRendering()
  }

  /// Makes the context of the document with the changes that the view hasn't rendered yet.
  private func applyDocumentChanges() {
    let changes = document.takeChanges()
    guard !changes.isEmpty else { return }
    // The CSS animations and the transitions that the changes start start at the time that the view displays. A view
    // that doesn't play animations, or that Reduce Motion holds, shows the new values at once.
    baseContext = baseContext.changingAttributes(
      changes, at: displayedTime.seconds,
      startsTransitions: configuration.animation != .none && !isHeldByReduceMotion)
    // Changes can make the animations last longer, after the clock stopped at their end.
    updatePlayback()
    resumeFinishedWaiters()
    // The size of the document can change with the attributes of its root element.
    invalidateIntrinsicContentSize()
  }

  /// Starts rendering the document at the time that the view displays.
  ///
  /// - Parameter reusesLayers: Whether the rendering shows the contents of the layers that the view shows where they
  ///   don't change, which a frame does. A new size, new data or a new content mode paints everything again.
  private func startRendering(reusesLayers: Bool = false) {
    let rect = bounds
    renderedSize = rect.size
    let generation = nextRenderingGeneration()
    let scale = displayScale
    let wideGamut = displaysWideGamut
    let capturedBase = baseContext
    let time = displayedTime
    renderedTime = time
    let fit = ContentFit(contentMode)
    let timeoutDuration = configuration.timeoutDuration
    let resources = resourceLoader
    let document = documentGeneration
    // The animations play in layers. A still frame is rendered into one image, as `takeSnapshot(rect:at:scale:)` renders it,
    // so that the view shows what a snapshot of the frame shows.
    let promoted = rendersLayers ? promoted : nil
    renderedInLayers = promoted != nil
    let painting = paintsFiltersIntoOwnLayers ? nil : painting
    let usesGPU = runsFiltersOnGPU && !isInBackground
    let previous = reusesLayers ? shownLayers : nil
    let previousNodes = reusesLayers ? shownNodes : RenderNodeCache()
    let previousStyled = reusesLayers ? shownStyled : nil
    isRendering = true
    let signpost = Self.signposter.beginInterval(
      "Render", id: Self.signposter.makeSignpostID(),
      "\(time.seconds, format: .fixed(precision: 3)) s into \(promoted == nil ? "an image" : "layers")")
    // The task starts off the main actor, so that the rendering doesn't wait for the other work of the app there, and
    // only the result is shown on it.
    let target = RenderingTarget(view: self)
    renderingTask = Task(priority: configuration.taskPriority) { @concurrent in
      if let promoted {
        let rendered = await SVGUIView.makeLayers(
          rect: rect, scale: scale, wideGamut: wideGamut, base: capturedBase, promoted: promoted, painting: painting,
          usesGPU: usesGPU,
          previous: previous, previousNodes: previousNodes, previousStyled: previousStyled, time: time, fit: fit,
          resources: resources, timeoutDuration: timeoutDuration)
        let result: Result<RenderedContainer, SVGRenderingError>
        switch rendered {
        case .success(.unchanged):
          // The view keeps showing the frame that looks the same.
          Self.signposter.endInterval("Render", signpost, "unchanged")
          await target.finishRendering(ofRendering: generation) { $0.unchangedFrameCount += 1 }
          return
        case .success(.changed(let layers, _, _, _)):
          result = .success(layers)
        case .failure(let error):
          result = .failure(error)
        }
        switch result {
        case .success(let layers) where Self.signposter.isEnabled:
          // Counting the layers that were painted takes time, so it's done only while the intervals are recorded.
          let painted = layers.paintedCount(since: previous)
          let filtered = layers.paintedContents.count(where: \.filteredOnGPU)
          Self.signposter.endInterval(
            "Render", signpost,
            "painted \(painted) of \(layers.paintedContents.count) layers, \(filtered) filtered on the GPU")
        case .success:
          Self.signposter.endInterval("Render", signpost)
        case .failure(let error):
          Self.signposter.endInterval("Render", signpost, "\(String(describing: error))")
        }
        await target.finishRendering(ofRendering: generation) { view in
          view.showLayers(result)
          if case .success(.changed(_, let nodes, let styled, let resolved)) = rendered {
            view.adoptStyleSheets(of: resolved, ofDocument: document)
            view.shownNodes = nodes
            view.shownStyled = styled
          }
        }
      } else {
        let result = await SVGUIView.makeImage(
          rect: rect, scale: scale, wideGamut: wideGamut, base: capturedBase, time: time,
          fit: fit, resources: resources, timeoutDuration: timeoutDuration
        )
        switch result {
        case .success: Self.signposter.endInterval("Render", signpost, "painted")
        case .failure(let error): Self.signposter.endInterval("Render", signpost, "\(String(describing: error))")
        }
        await target.finishRendering(ofRendering: generation) { view in
          if case .success(let rendered) = result {
            view.adoptStyleSheets(of: rendered.resolved, ofDocument: document)
          }
          view.show(result.map(\.image))
        }
      }
    }
  }

  /// Shows the result of a rendering, unless a newer rendering has started since, and starts the frame that waits
  /// for it. A rendering for an old size or old data that finished before it was cancelled doesn't replace a newer
  /// image.
  private func finishRendering(ofRendering generation: Int, show: @MainActor (SVGUIView) -> Void) {
    guard generation == renderingGeneration else { return }
    isRendering = false
    show(self)
    if needsFrame {
      needsFrame = false
      startRendering(reusesLayers: true)
    }
  }

  /// Renders the frame at the time that the view displays, after the rendering in progress if there is one.
  ///
  /// A frame doesn't stop the rendering in progress, unlike a new size or new data, so that the view shows
  /// frames even when rendering one takes longer than the display shows it.
  private func renderFrame() {
    if isRendering {
      if needsFrame {
        Self.signposter.emitEvent("Skipped frame")
      }
      needsFrame = true
    } else {
      startRendering(reusesLayers: true)
    }
  }

  deinit {
    // The rendering holds the view weakly, so without this it would go on until the timeout.
    renderingTask?.cancel()
    for waiter in finishWaiters {
      waiter.continuation.resume()
    }
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
    resumeFinishedWaiters()
  }

  /// Whether Reduce Motion holds the animations at time zero.
  private var isHeldByReduceMotion: Bool {
    configuration.animation != .none && !configuration.playsWithReduceMotion && isReduceMotionEnabled()
  }

  /// The time of the animations that the view displays.
  private var displayedTime: Duration {
    configuration.animation == .none || isHeldByReduceMotion ? .zero : currentTime
  }

  /// Whether the animations play: the view plays them, they haven't ended, and Reduce Motion doesn't hold them.
  private var playsAnimations: Bool {
    configuration.animation != .none && isPlaying && currentTime.seconds < animationEnd && !isHeldByReduceMotion
  }

  /// Whether the view shows its document in layers, which it does while its animations play, whether it can be seen
  /// or not, so that it doesn't render again when it's seen again.
  private var rendersLayers: Bool {
    playsAnimations || showsStillFramesInLayers && configuration.animation != .none
  }

  /// Whether the animations advance: they play, and the view can be seen.
  private var advances: Bool {
    playsAnimations && window != nil && !isHidden && bounds.width > 0 && bounds.height > 0 && !isInBackground
  }

  /// Starts or stops the clock, and renders the displayed time if it changed, or the frame in the other way if the
  /// animations start or stop playing.
  private func updatePlayback() {
    clock.isRunning = advances
    if let renderedTime, renderedTime != displayedTime || renderedInLayers != rendersLayers {
      renderFrame()
    }
  }

  private func startObservingClock() {
    clock.onFrame = { [weak self] elapsed in
      guard let self else { return }
      currentTime += elapsed
      renderFrame()
      resumeFinishedWaiters()
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
      shownLayers = nil
      shownNodes = RenderNodeCache()
      shownStyled = nil
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
      shownLayers = layers
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
      shownLayers = nil
      shownNodes = RenderNodeCache()
      shownStyled = nil
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
  /// The image includes every change made to ``document`` so far, even the
  /// ones that the view hasn't rendered yet.
  ///
  /// The image is rendered with the view's current `contentMode`, and the
  /// view's displayed contents do not change. Its width and height in pixels
  /// are those of the rectangle times the scale, which is the scale of the
  /// view's screen by default, or of the main screen for a view that isn't on
  /// one. The image itself has a scale of 1, so its size in
  /// points is its size in pixels.
  ///
  /// A view doesn't have to be on the screen to render: pass the rectangle to
  /// render into. Without one, the view renders into its frame, which is empty
  /// for a view that has no frame, and the method throws
  /// ``SVGRenderingError/zeroSizedRect``.
  ///
  /// The image is in sRGB, as the view shows it. On a screen of a wide gamut,
  /// such as the screen of the view, or the main screen for a view that isn't
  /// on one, a document that paints colors outside sRGB, such as
  /// `color(display-p3 1 0 0)`, or images of a wide gamut, renders into an
  /// image in Display P3 instead, which shows those colors.
  ///
  /// The time starts at zero when the document is loaded. A view that doesn't
  /// play its animations displays time zero, and a view that plays them
  /// displays ``currentTime``. A document without animations looks the same at
  /// any time, and ``SVGDocument/animationEnd`` is the time after which a
  /// document looks the same.
  ///
  /// - Parameters:
  ///   - rect: The rectangle to render into. Pass `nil` to use the view's
  ///     frame.
  ///   - time: The time of the document's animations.
  ///   - scale: The number of pixels in a point of the image. Pass `nil` to use
  ///     the scale of the view's screen, or of the main screen for a view that
  ///     isn't on one.
  /// - Returns: The rendered image.
  /// - Throws: ``SVGRenderingError/missingRootElement`` if the document has no
  ///   root `svg` element, ``SVGRenderingError/zeroSizedRect`` if the rectangle
  ///   has no width or no height in pixels at the scale,
  ///   ``SVGRenderingError/timedOut`` if rendering takes longer than
  ///   ``SVGUIViewConfiguration/timeoutDuration``, or
  ///   ``SVGRenderingError/cancelled`` if the task that calls this method is
  ///   cancelled before rendering finishes, or
  ///   ``SVGRenderingError/allocationFailed`` if the memory for the image
  ///   couldn't be allocated.
  public func takeSnapshot(
    rect: CGRect? = nil, at time: Duration = .zero, scale: CGFloat? = nil
  ) async throws(SVGRenderingError) -> UIImage {
    UIImage(cgImage: try await snapshot(rect: rect, at: time, scale: scale))
  }

  /// Renders the current SVG document into a Core Graphics image, as it is at
  /// a time of its animations.
  ///
  /// This renders the image that ``takeSnapshot(rect:at:scale:)`` does, without
  /// a `UIImage` around it, such as for the frames of a video, whose pixel
  /// buffers are made from Core Graphics images:
  ///
  /// ```swift
  /// let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
  /// let frame = try await svgView.takeCGImageSnapshot(
  ///   rect: rect, at: .milliseconds(500), scale: 2)
  /// // frame.width and frame.height are 640.
  /// ```
  ///
  /// - Parameters:
  ///   - rect: The rectangle to render into. Pass `nil` to use the view's
  ///     frame.
  ///   - time: The time of the document's animations.
  ///   - scale: The number of pixels in a point of the image. Pass `nil` to use
  ///     the scale of the view's screen, or of the main screen for a view that
  ///     isn't on one.
  /// - Returns: The rendered image, whose width and height in pixels are those
  ///   of the rectangle times the scale.
  /// - Throws: The errors that ``takeSnapshot(rect:at:scale:)`` throws.
  public func takeCGImageSnapshot(
    rect: CGRect? = nil, at time: Duration = .zero, scale: CGFloat? = nil
  ) async throws(SVGRenderingError) -> CGImage {
    try await snapshot(rect: rect, at: time, scale: scale)
  }

  /// Renders the document with every change into an image of the rectangle at the scale, for the snapshots.
  ///
  /// - Parameter wideGamut: Whether the image shows colors outside sRGB, or `nil` to show them as the screen of the
  ///   view does.
  func snapshot(
    rect: CGRect?, at time: Duration, scale: CGFloat?, wideGamut: Bool? = nil
  ) async throws(SVGRenderingError) -> CGImage {
    let rect = rect ?? frame
    let scale = scale ?? displayScale
    let wideGamut = wideGamut ?? displaysWideGamut
    applyDocumentChanges()
    let capturedBase = baseContext
    let fit = ContentFit(contentMode)
    let timeoutDuration = configuration.timeoutDuration
    let document = documentGeneration
    let rendered = try await SVGUIView.makeImage(
      rect: rect, scale: scale, wideGamut: wideGamut, base: capturedBase, time: time,
      fit: fit, resources: resourceLoader, timeoutDuration: timeoutDuration
    ).get()
    adoptStyleSheets(of: rendered.resolved, ofDocument: document)
    return rendered.image
  }

  /// Keeps the context that a rendering made with the style sheets in other files that it read, so that the next
  /// renderings don't read them again, unless the view shows another document since.
  ///
  /// The document API can have changed the document while the style sheets were read, so the context of the view
  /// takes the style sheets of that context.
  private func adoptStyleSheets(of resolved: SVGBaseContext?, ofDocument generation: Int) {
    guard let resolved, generation == documentGeneration, baseContext.needsExternalStyleSheets else { return }
    baseContext =
      baseContext.hasSameDocument(as: resolved)
      ? resolved : baseContext.adoptingStyleSheets(of: resolved, at: displayedTime.seconds)
    // The style sheets can set the size of the root element.
    invalidateIntrinsicContentSize()
  }

  /// Reads the files that the document refers to for a rendering, as the configuration allows.
  private var resourceLoader: ExternalResourceLoader {
    let resources = configuration.externalResources
    // A document without a base URL reads no files, and only the network by absolute URLs.
    guard baseURL != nil || resources.network else { return .none }
    return ExternalResourceLoader(
      baseURL: baseURL, folder: baseURL.flatMap(resources.folder(forDocumentAt:)), allowsNetwork: resources.network,
      cache: resourceCache, fetch: Self.resourceFetch ?? ExternalResourceLoader.defaultFetch)
  }

  /// The number of pixels in a point of the screen of the view, or of the traits of the app for a view that isn't on
  /// a screen, or of the main screen if neither has one.
  private var displayScale: CGFloat {
    if traitCollection.displayScale > 0 { return traitCollection.displayScale }
    if UITraitCollection.current.displayScale > 0 { return UITraitCollection.current.displayScale }
    return UIScreen.main.scale
  }

  /// Whether the screen of the view shows colors outside sRGB, or the main screen, for a view that isn't on one.
  private var displaysWideGamut: Bool {
    let gamut = traitCollection.displayGamut
    return (gamut == .unspecified ? UIScreen.main.traitCollection.displayGamut : gamut) == .P3
  }

  /// Renders the document into an image.
  ///
  /// - Parameter wideGamut: Whether the image shows colors outside sRGB, in Display P3, where the document paints
  ///   them. An image of a document in sRGB is in sRGB anyway.
  @concurrent
  private static func makeImage(
    rect: CGRect,
    scale: CGFloat,
    wideGamut: Bool,
    base: SVGBaseContext,
    time: Duration,
    fit: ContentFit,
    resources: ExternalResourceLoader,
    timeoutDuration: Duration
  ) async -> Result<RenderedImage, SVGRenderingError> {
    guard base.root != nil else { return .failure(.missingRootElement) }

    // `CGContext` cannot make a bitmap without a pixel.
    guard (rect.width * scale).rounded(.up) > 0, (rect.height * scale).rounded(.up) > 0 else {
      return .failure(.zeroSizedRect)
    }

    let rendered = await withRenderingTimeout(timeoutDuration) { () async -> Result<RenderedImage, SVGRenderingError>? in
      // The style sheets in other files and the computed values at the time are found in the task, so that the
      // timeout stops them too.
      let resolved =
        base.needsExternalStyleSheets
        ? await base.resolvingExternalStyleSheets(loader: resources, at: time.seconds) : base
      guard !Task.isCancelled else { return nil }
      let builder = RenderTreeBuilder(
        base: resolved.at(time: time.seconds), viewPort: rect, scale: scale, resources: resources)
      guard let tree = await builder.build(fit: fit) else { return nil }
      // The tree tells which colors the bitmap shows.
      let space = CGColorSpace.rendering(wideGamut: wideGamut && tree.usesWideGamut)
      guard let graphics = CGContext.bitmap(size: rect.size, scale: scale, space: space) else {
        return .failure(.allocationFailed)
      }
      graphics.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, CGFloat(graphics.height)))
      await CGPainter(scale: scale).paint(tree, into: graphics)
      guard !Task.isCancelled else { return nil }
      // Making the image copies the bitmap, which can fail as allocating it can.
      guard let image = graphics.makeImage() else { return .failure(.allocationFailed) }
      return .success(RenderedImage(image: image, resolved: base.needsExternalStyleSheets ? resolved : nil))
    }
    return rendered.flatMap { $0 }
  }

  /// The image of a rendering, and the context with the style sheets in other files that it read, or `nil` if it
  /// read none.
  private struct RenderedImage: Sendable {
    let image: CGImage
    let resolved: SVGBaseContext?
  }

  /// Renders the document at a time into layers: the layers of the elements whose transform or opacity changes, and
  /// the contents of the layers between them, which show the contents of the previous layers where they don't
  /// change, and the render nodes that the next frame can reuse. A frame whose animated values are the same as those
  /// of the frame that the view shows isn't rendered.
  ///
  /// - Parameters:
  ///   - painting: The elements whose painting changes in other ways than their compositing, or `nil` if any painting
  ///     can change.
  ///   - wideGamut: Whether the layers show colors outside sRGB, in Display P3, where the frame paints them.
  ///   - usesGPU: Whether the filters of the elements that are painted into layers of their own run on the GPU.
  ///   - previousStyled: The document at the time of the frame that the view shows, from the same context, or `nil`
  ///     to render the frame anyway.
  @concurrent
  private static func makeLayers(
    rect: CGRect,
    scale: CGFloat,
    wideGamut: Bool,
    base: SVGBaseContext,
    promoted: Set<ElementID>,
    painting: Set<ElementID>?,
    usesGPU: Bool,
    previous: RenderedContainer?,
    previousNodes: RenderNodeCache,
    previousStyled: SVGBaseContext?,
    time: Duration,
    fit: ContentFit,
    resources: ExternalResourceLoader,
    timeoutDuration: Duration
  ) async -> Result<LayerFrame, SVGRenderingError> {
    guard base.root != nil else { return .failure(.missingRootElement) }
    guard (rect.width * scale).rounded(.up) > 0, (rect.height * scale).rounded(.up) > 0 else {
      return .failure(.zeroSizedRect)
    }
    return await withRenderingTimeout(timeoutDuration) {
      let signposter = Self.signposter
      // Reading the style sheets is skipped where there are none, as nearly every frame does.
      let readsStyleSheets = base.needsExternalStyleSheets
      let resolved =
        readsStyleSheets ? await base.resolvingExternalStyleSheets(loader: resources, at: time.seconds) : base
      guard !Task.isCancelled else { return nil }
      let base = signposter.withIntervalSignpost("Style") { resolved.at(time: time.seconds) }
      // A frame whose animated values are the same as the frame that the view shows looks the same.
      if let previousStyled, base.hasSameAnimatedValues(as: previousStyled) { return LayerFrame.unchanged }
      let buildInterval = signposter.beginInterval("Build")
      let tree = await RenderTreeBuilder(
        base: base, viewPort: rect, scale: scale, reusing: previousNodes, resources: resources
      ).build(fit: fit)
      signposter.endInterval("Build", buildInterval)
      guard let tree else { return nil }
      let plan = signposter.withIntervalSignpost("Plan") {
        LayerPlanner(promoted: promoted, painting: painting, scale: scale).plan(tree, in: rect)
      }
      let paintInterval = signposter.beginInterval("Paint")
      defer { signposter.endInterval("Paint", paintInterval) }
      let wideGamut = wideGamut && tree.usesWideGamut
      guard
        let layers = await plan.painted(
          scale: scale, wideGamut: wideGamut, reusing: previous, runsFiltersOnGPU: usesGPU)
      else { return nil }
      return LayerFrame.changed(
        layers: layers, nodes: tree.reusableNodes, styled: base,
        resolved: readsStyleSheets ? resolved : nil)
    }
  }

  /// The view of a rendering, which the rendering holds weakly, and only holds on the main actor while it shows its
  /// result, so that the view is never released off the main thread.
  private struct RenderingTarget: Sendable {
    weak var view: SVGUIView?

    /// Shows the result of the rendering in the view, unless the view has been released.
    @MainActor
    func finishRendering(ofRendering generation: Int, show: @MainActor (SVGUIView) -> Void) {
      view?.finishRendering(ofRendering: generation, show: show)
    }
  }

  /// The layers of a frame, with the render nodes that the next frame can reuse and the document at its time, or
  /// none for a frame that looks the same as the one that the view shows.
  private enum LayerFrame: Sendable {
    /// A frame, with the context with the style sheets in other files that the rendering read, or `nil`.
    case changed(layers: RenderedContainer, nodes: RenderNodeCache, styled: SVGBaseContext, resolved: SVGBaseContext?)
    case unchanged
  }
}

extension SVGUIView: DocumentHost {
  func documentDidChange() {
    // The layer is displayed once for the changes made until then.
    setNeedsDisplay()
    // The tasks that wait for the animations go on after the changes, also in a view whose layer isn't displayed, such
    // as one that isn't on screen. The changes made until then are applied together.
    guard !finishWaiters.isEmpty, !appliesChangesForWaiters else { return }
    appliesChangesForWaiters = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      appliesChangesForWaiters = false
      applyDocumentChanges()
    }
  }

  func cssAnimations() -> [CSSAnimationID] {
    applyDocumentChanges()
    return baseContext.cssAnimations()
  }

  func documentAnimationEnd() -> Double {
    applyDocumentChanges()
    return animationEnd
  }

  func playback(of id: CSSAnimationID) -> (playback: AnimationPlayback, time: Double)? {
    applyDocumentChanges()
    return baseContext.playback(of: id).map { ($0, displayedTime.seconds) }
  }

  func changePlayback(of id: CSSAnimationID, _ change: (inout AnimationPlayback, Double) -> Void) {
    applyDocumentChanges()
    guard var playback = baseContext.playback(of: id) else { return }
    let previous = playback
    change(&playback, displayedTime.seconds)
    guard playback != previous else { return }
    animationsDidChange(baseContext.settingPlayback(playback, of: id))
  }

  func beginSMILAnimation(_ element: ElementID) {
    applyDocumentChanges()
    guard let context = baseContext.beginningSMILAnimation(element, at: displayedTime.seconds) else { return }
    animationsDidChange(context)
  }

  func endSMILAnimation(_ element: ElementID) {
    applyDocumentChanges()
    guard let context = baseContext.endingSMILAnimation(element, at: displayedTime.seconds) else { return }
    animationsDidChange(context)
  }

  /// Shows the document with animations that play in another way, and runs the clock while they change.
  private func animationsDidChange(_ context: SVGBaseContext) {
    baseContext = context
    // Only the values of the animated elements change, so a frame shows the layers that don't change as they are.
    if configuration.animation == .none {
      setNeedsDisplay()
    } else {
      renderFrame()
    }
    updatePlayback()
    resumeFinishedWaiters()
  }

  func waitUntilFinished(_ id: CSSAnimationID) async {
    applyDocumentChanges()
    guard !baseContext.isFinished(id, at: displayedTime.seconds) else { return }
    let token = nextFinishWaiterToken
    nextFinishWaiterToken += 1
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // A task that is cancelled before it waits doesn't wait.
        guard !Task.isCancelled else { return continuation.resume() }
        finishWaiters.append((token, id, continuation))
      }
    } onCancel: { [weak self] in
      // The handler can run on any thread, and runs before the task waits if it's cancelled already, so the waiter is
      // resumed on the main actor, after it's added.
      Task { @MainActor in self?.resumeFinishWaiter(token) }
    }
  }

  /// Lets the task go on that waits with a token, if it still waits.
  private func resumeFinishWaiter(_ token: Int) {
    guard let index = finishWaiters.firstIndex(where: { $0.token == token }) else { return }
    finishWaiters.remove(at: index).continuation.resume()
  }

  /// Lets the tasks go on that wait for the animations that have finished at the time that the view displays, or
  /// that no element runs.
  fileprivate func resumeFinishedWaiters() {
    guard !finishWaiters.isEmpty else { return }
    let time = displayedTime.seconds
    resumeWaiters { baseContext.isFinished($0, at: time) }
  }

  /// Lets the tasks go on that wait for the animations that pass a check.
  fileprivate func resumeWaiters(where finished: (CSSAnimationID) -> Bool) {
    var waiting = [(token: Int, id: CSSAnimationID, continuation: CheckedContinuation<Void, Never>)]()
    for waiter in finishWaiters {
      if finished(waiter.id) {
        waiter.continuation.resume()
      } else {
        waiting.append(waiter)
      }
    }
    finishWaiters = waiting
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
      self.init(preserveAspectRatio: .none)
    case .scaleAspectFit:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet))
    case .scaleAspectFill:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .slice))
    case .redraw:
      // The document is stretched to the bounds, as with `scaleToFill`.
      self.init(preserveAspectRatio: .none)
    case .center:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid))
    case .top:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .min))
    case .bottom:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .max))
    case .left:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .min, yAlign: .mid))
    case .right:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .max, yAlign: .mid))
    case .topLeft:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .min, yAlign: .min))
    case .topRight:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .max, yAlign: .min))
    case .bottomLeft:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .min, yAlign: .max))
    case .bottomRight:
      self.init(preserveAspectRatio: PreserveAspectRatio(xAlign: .max, yAlign: .max))
    @unknown default:
      self.init(preserveAspectRatio: .none)
    }
  }
}

/// The context of a document, with the values that a view finds in it to play its animations, which can be made off
/// the main actor.
private struct LoadedDocument: Sendable {
  let context: SVGBaseContext
  /// The time in seconds after which the document doesn't change.
  let animationEnd: Double
  /// The elements whose transform or opacity can change.
  let promoted: Set<ElementID>
  /// The elements whose painting changes in other ways.
  let painting: Set<ElementID>

  init(context: SVGBaseContext) {
    self.context = context
    animationEnd = context.animationEnd()
    promoted = context.elementsWithAnimatedCompositing()
    painting = context.elementsWithAnimatedPainting()
  }
}
