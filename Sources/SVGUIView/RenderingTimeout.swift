import Foundation

/// Renders in a task that the timeout and the cancellation of the caller stop.
///
/// - Parameters:
///   - timeoutDuration: The longest time that the rendering may take.
///   - render: The rendering, which returns `nil` when it's stopped, and a value otherwise.
/// - Returns: The value, or ``SVGRenderingError/timedOut`` or ``SVGRenderingError/cancelled`` if the rendering was
///   stopped.
func withRenderingTimeout<Value: Sendable>(
  _ timeoutDuration: Duration, _ render: sending @escaping @isolated(any) () async -> Value?
) async -> Result<Value, SVGRenderingError> {
  let drawTask = Task<Value?, Never>(operation: render)

  // Time out on a dispatch queue rather than in a task, so that the timeout fires even while renderings
  // occupy every thread of the cooperative thread pool. Those threads also count against dispatch queues of
  // the same quality of service, so the queue is above the highest task priority that renderings can have.
  // A timer source releases its handler, and with it `drawTask` and its result, as soon as it is cancelled,
  // whereas a cancelled work item stays on the queue until its deadline.
  let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
  timeout.setEventHandler { drawTask.cancel() }
  timeout.schedule(deadline: .now() + timeoutDuration.dispatchTimeInterval)
  timeout.activate()
  let value = await withTaskCancellationHandler {
    await drawTask.value
  } onCancel: {
    drawTask.cancel()
  }
  timeout.cancel()
  // Only the timeout and the cancellation of the caller cancel `drawTask`, and a rendering returns a value
  // otherwise, so `nil` means that it was cancelled or timed out.
  guard let value else { return .failure(Task.isCancelled ? .cancelled : .timedOut) }
  return .success(value)
}
