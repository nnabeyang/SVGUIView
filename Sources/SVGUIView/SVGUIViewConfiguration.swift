/// Settings that control how an ``SVGUIView`` renders its image.
public struct SVGUIViewConfiguration: Sendable {
  /// The priority of the background task that renders the image.
  public let taskPriority: TaskPriority
  /// The longest time a single rendering may take.
  ///
  /// When rendering takes longer, it is cancelled and nothing is drawn.
  public let timeoutDuration: Duration

  /// Creates a configuration.
  ///
  /// - Parameters:
  ///   - taskPriority: The priority of the background rendering task.
  ///   - timeoutDuration: The longest time a single rendering may take.
  public init(taskPriority: TaskPriority = .medium, timeoutDuration: Duration = .seconds(1)) {
    self.taskPriority = taskPriority
    self.timeoutDuration = timeoutDuration
  }
}
