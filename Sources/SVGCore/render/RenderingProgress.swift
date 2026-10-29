/// What a rendering reports while it paints, which tests observe to check where a cancelled rendering stops.
package enum RenderingProgress {
  /// Called after each primitive of a filter that a rendering in the task runs, or `nil` to report nothing.
  @TaskLocal package static var onFilterPrimitive: (@Sendable () -> Void)?
}
