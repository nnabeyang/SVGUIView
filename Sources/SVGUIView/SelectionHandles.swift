import UIKit

/// An end of the selection, whose handle a person drags.
enum SelectionEnd {
  case start
  case end
}

extension SVGUIView {
  /// How far from the caret of an end of the selection its handle is held: its knob sticks out of the line by about
  /// its size, and a finger holds it a little around.
  static let selectionHandleReach: CGFloat = 24

  /// The end of the selection whose handle is at a point of the view, the closer one if both are, or `nil` if neither
  /// is or nothing is selected.
  func selectionHandle(at point: CGPoint) -> SelectionEnd? {
    guard let session = textEditing, !session.selection.isEmpty else { return nil }
    let start = caret(at: session.selection.lowerBound, in: session).squaredDistance(to: point)
    let end = caret(at: session.selection.upperBound, in: session).squaredDistance(to: point)
    guard min(start, end) <= Self.selectionHandleReach * Self.selectionHandleReach else { return nil }
    return start <= end ? .start : .end
  }

  /// Moves an end of the selection to the position of the text closest to a point of the view, along the angle of the
  /// text, and keeps a character selected, as dragging a handle does.
  func moveSelection(_ end: SelectionEnd, to point: CGPoint) {
    guard let session = textEditing, !session.selection.isEmpty,
      let position = (closestPosition(to: point) as? TextEditingPosition)?.offset
    else { return }
    let selection =
      switch end {
      case .start: min(position, session.selection.upperBound - 1)..<session.selection.upperBound
      case .end: session.selection.lowerBound..<max(position, session.selection.lowerBound + 1)
      }
    guard selection != session.selection else { return }
    session.inputDelegate?.selectionWillChange(self)
    session.selection = selection
    session.typingAttributes = nil
    session.inputDelegate?.selectionDidChange(self)
    session.display?.setNeedsSelectionUpdate()
  }

  /// The position of an end of the selection.
  func position(of end: SelectionEnd) -> Int? {
    textEditing.map { end == .start ? $0.selection.lowerBound : $0.selection.upperBound }
  }
}

/// The dragging of the handles of the selection where the text interaction doesn't drag them: on a turned text,
/// whose handles the interaction finds where the text would be without its angle, and from the knob of a handle that
/// sticks out of the lines of a text that isn't turned. The text interaction drags the others.
extension TextEditingSession: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard gesture === handlePan, let view else { return true }
    handleTouchDown = touch.location(in: view)
    return view.selectionHandle(at: handleTouchDown) != nil
  }

  func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    guard gesture === handlePan, let view else { return true }
    guard let end = view.selectionHandle(at: handleTouchDown) else { return false }
    // The interaction drags the handles of a text that isn't turned from where they're in the lines.
    if angle == 0, view.editedTextArea(of: self).contains(handleTouchDown) { return false }
    draggedEnd = end
    return true
  }

  /// The gestures of the text interaction wait for the dragging of a handle, so that they don't move the caret where
  /// it begins.
  func gestureRecognizer(
    _ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
  ) -> Bool {
    gesture === handlePan && other.view === view && other !== gesture
  }

  @objc func dragHandle(_ gesture: UIPanGestureRecognizer) {
    guard let view, let end = draggedEnd, let offset = view.position(of: end) else { return }
    let point = gesture.location(in: view)
    switch gesture.state {
    case .began:
      let caret = view.caret(at: offset, in: self)
      handleOffset = CGVector(dx: caret.rect.midX - handleTouchDown.x, dy: caret.rect.midY - handleTouchDown.y)
      handleLoupe = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: nil, in: view)
      fallthrough
    case .changed:
      let target = CGPoint(x: point.x + handleOffset.dx, y: point.y + handleOffset.dy)
      view.moveSelection(end, to: target)
      if let moved = view.position(of: end) {
        let caret = view.caretRect(for: TextEditingPosition(moved))
        handleLoupe?.move(to: CGPoint(x: caret.midX, y: caret.midY), withCaretRect: caret, trackingCaret: true)
      }
    default:
      handleLoupe?.invalidate()
      handleLoupe = nil
      draggedEnd = nil
    }
  }
}
