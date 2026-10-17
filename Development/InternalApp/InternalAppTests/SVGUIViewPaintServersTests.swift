import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewPaintServersTests {
    @Test(arguments: SVGFile.all(in: "basic", "paint-servers", "linearGradient"))
    func linearGradient(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "paint-servers", "pattern"))
    func pattern(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "paint-servers", "radialGradient"))
    func radialGradient(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
