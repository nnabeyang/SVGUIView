public struct SVGUIViewConfiguration: Sendable {
  public let taskPriority: TaskPriority
  public let timeoutDuration: Duration

  public init(taskPriority: TaskPriority = .medium, timeoutDuration: Duration = .seconds(1)) {
    self.taskPriority = taskPriority
    self.timeoutDuration = timeoutDuration
  }
}
