import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewPaintingTests {
    @Test(arguments: SVGFile.all(in: "basic", "painting", "fill"))
    func fill(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "fill-opacity"))
    func fillOpacity(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
