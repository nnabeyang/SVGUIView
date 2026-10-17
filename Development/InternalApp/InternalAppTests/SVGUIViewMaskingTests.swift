import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewMaskingTests {
    @Test(arguments: SVGFile.all(in: "basic", "masking", "clipPath"))
    func clipPath(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "masking", "mask"))
    func mask(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
