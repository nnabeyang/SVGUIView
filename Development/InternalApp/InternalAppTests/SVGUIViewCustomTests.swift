import Testing

extension SnapshotTests {
  /// The tests written for SVGUIView, for cases that the tests from other projects don't cover.
  @MainActor
  @Suite
  struct SVGUIViewCustomTests {
    @Test(arguments: SVGFile.all(root: "custom", in: "masking"))
    func masking(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(root: "custom", in: "text"))
    func text(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(root: "custom", in: "transform"))
    func transform(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    /// The times that documents with animations are rendered at, which the arguments of a test read from outside
    /// the main actor.
    nonisolated private static let times: [Duration] = [
      .zero, .milliseconds(500), .seconds(1), .milliseconds(1500), .milliseconds(2500),
    ]

    @Test(arguments: SVGFile.all(root: "custom", in: "animation"), times)
    func animation(_ file: SVGFile, at time: Duration) async throws {
      try await assertSVGSnapshot(of: file, at: time)
    }
  }
}
