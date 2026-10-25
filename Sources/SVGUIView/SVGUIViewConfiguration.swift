/// Settings that control how an ``SVGUIView`` renders its image.
public struct SVGUIViewConfiguration: Sendable {
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

  /// Creates a configuration.
  ///
  /// - Parameters:
  ///   - taskPriority: The priority of the background rendering task.
  ///   - timeoutDuration: The longest time a single rendering may take. The
  ///     default is 10 seconds.
  public init(taskPriority: TaskPriority = .medium, timeoutDuration: Duration = .seconds(10)) {
    self.taskPriority = taskPriority
    self.timeoutDuration = timeoutDuration
  }
}
