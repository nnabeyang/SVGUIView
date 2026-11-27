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

  /// Moves the end of the selection that is dragged to the position of the text closest to a point of the view, along
  /// the angle of the text, from the other end, which stays where it is, as dragging a handle does. The ends swap where
  /// the dragged one passes the other one, and the selection stays as it is where they meet, so that a character stays
  /// selected.
  ///
  /// - Parameter anchor: The position of the end that isn't dragged.
  /// - Returns: The end that the dragged position is now.
  @discardableResult
  func moveSelection(from anchor: Int, to point: CGPoint) -> SelectionEnd? {
    guard let session = textEditing, !session.selection.isEmpty,
      let position = (closestPosition(to: point) as? TextEditingPosition)?.offset
    else { return nil }
    guard position != anchor else {
      return session.selection.lowerBound == anchor ? .end : .start
    }
    let selection = min(position, anchor)..<max(position, anchor)
    if selection != session.selection {
      session.inputDelegate?.selectionWillChange(self)
      session.selection = selection
      session.typingAttributes = nil
      session.inputDelegate?.selectionDidChange(self)
      session.display?.setNeedsSelectionUpdate()
    }
    return position < anchor ? .start : .end
  }

  /// The gestures of the view don't begin on a handle that the view drags, such as the dragging of the text
  /// interaction, which finds the handles of a turned text where the text would be without its angle.
  override public func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    if let session = textEditing, gesture !== session.handlePan, session.touchedHandle != nil {
      return false
    }
    return super.gestureRecognizerShouldBegin(gesture)
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
  /// The end of the selection whose handle the view drags from a point: a handle of a turned text, or the knob of a
  /// handle out of the lines of a text that isn't turned, whose handles the interaction drags from the lines.
  func handleDragged(from point: CGPoint) -> SelectionEnd? {
    guard let view, let end = view.selectionHandle(at: point) else { return nil }
    if angle == 0, view.editedTextArea(of: self).contains(point) { return nil }
    return end
  }

  func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard gesture === handlePan, let view else { return true }
    // Each touch on the view finds whether it's on a handle that the view drags, which the other gestures of the
    // view don't begin on.
    handleTouchDown = touch.location(in: view)
    touchedHandle = handleDragged(from: handleTouchDown)
    return touchedHandle != nil
  }

  func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    guard gesture === handlePan else { return true }
    guard let end = touchedHandle else { return false }
    draggedEnd = end
    return true
  }

  /// The gestures of the text interaction, on the view and on the views of its handles, wait for the dragging of a
  /// handle, so that they don't move the caret or drag the handle where it begins.
  func gestureRecognizer(
    _ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
  ) -> Bool {
    guard gesture === handlePan, other !== gesture, let view, let otherView = other.view else { return false }
    return otherView.isDescendant(of: view)
  }

  @objc func dragHandle(_ gesture: UIPanGestureRecognizer) {
    guard let view, let end = draggedEnd, let offset = view.position(of: end) else { return }
    let point = gesture.location(in: view)
    switch gesture.state {
    case .began:
      // The other end stays where it is while the dragged one moves.
      handleAnchor = end == .start ? selection.upperBound : selection.lowerBound
      let caret = view.caret(at: offset, in: self)
      handleOffset = CGVector(dx: caret.rect.midX - handleTouchDown.x, dy: caret.rect.midY - handleTouchDown.y)
      handleLoupe = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: nil, in: view)
      fallthrough
    case .changed:
      let target = CGPoint(x: point.x + handleOffset.dx, y: point.y + handleOffset.dy)
      if let moved = view.moveSelection(from: handleAnchor, to: target) {
        draggedEnd = moved
      }
      if let draggedEnd, let moved = view.position(of: draggedEnd) {
        let caret = view.caretRect(for: TextEditingPosition(moved))
        handleLoupe?.move(to: CGPoint(x: caret.midX, y: caret.midY), withCaretRect: caret, trackingCaret: true)
      }
    default:
      handleLoupe?.invalidate()
      handleLoupe = nil
      draggedEnd = nil
      touchedHandle = nil
    }
  }
}
