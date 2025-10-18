public struct ParserState {
  public var position: Int
  public var currentLineStartPosition: Int
  public var currentLineNumber: Int
  public var atStartOf: BlockType?

  public init(position: Int, currentLineStartPosition: Int, currentLineNumber: Int, atStartOf: BlockType?) {
    self.position = position
    self.currentLineStartPosition = currentLineStartPosition
    self.currentLineNumber = currentLineNumber
    self.atStartOf = atStartOf
  }

  public var sourcePosition: SourcePosition {
    SourcePosition(position)
  }

  public var sourceLocation: SourceLocation {
    SourceLocation(
      line: currentLineNumber,
      column: position - currentLineStartPosition + 1
    )
  }
}

public enum ParseUntilErrorBehavior: Equatable {
  case consume
  case stop
}
