import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewW3CTests {
    @Test(arguments: SVGFile.all(in: "1.1F2"))
    func svg1_1F2(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    /// The files with animations, at the times that their tests check.
    @Test(arguments: SVGFile.timed(in: "1.1F2"))
    func animations1_1F2(_ file: SVGFile, at time: Duration) async throws {
      try await assertSVGSnapshot(of: file, at: time)
    }
  }
}
