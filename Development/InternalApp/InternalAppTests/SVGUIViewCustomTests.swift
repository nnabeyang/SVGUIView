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
  }
}
