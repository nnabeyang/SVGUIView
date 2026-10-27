/// Settings that control how an ``SVGUIView`` renders its image.
public struct SVGUIViewConfiguration: Sendable {
  /// Whether a view plays the animations of its document.
  public enum AnimationMode: Sendable, Equatable {
    /// The view displays the document at time zero, as a still image.
    case none
    /// The view plays the animations of its document.
    case play
    /// The view holds the animations of its document at the current time, until
    /// ``SVGUIView/play()`` is called.
    case paused
  }

  /// The priority of the background task that renders the image.
  public let taskPriority: TaskPriority
  /// The longest time a single rendering may take.
  ///
  /// When rendering takes longer, it is cancelled. The view keeps the image
  /// that it shows, and ``SVGUIView/takeSnapshot(rect:at:)`` throws
  /// ``SVGRenderingError/timedOut``.
  ///
  /// The default is 10 seconds. It stops a rendering that would take far
  /// too long, and leaves enough time to render an ordinary document on a
  /// slow device or under load.
  public let timeoutDuration: Duration
  /// Whether the view plays the animations of its document.
  ///
  /// The default is ``AnimationMode/none``, which displays the document at
  /// time zero.
  public let animation: AnimationMode

  /// Creates a configuration.
  ///
  /// - Parameters:
  ///   - taskPriority: The priority of the background rendering task.
  ///   - timeoutDuration: The longest time a single rendering may take. The
  ///     default is 10 seconds.
  ///   - animation: Whether the view plays the animations of its document.
  ///     The default is ``AnimationMode/none``.
  public init(
    taskPriority: TaskPriority = .medium, timeoutDuration: Duration = .seconds(10), animation: AnimationMode = .none
  ) {
    self.taskPriority = taskPriority
    self.timeoutDuration = timeoutDuration
    self.animation = animation
  }
}
