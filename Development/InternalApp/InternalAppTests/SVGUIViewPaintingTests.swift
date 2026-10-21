import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewPaintingTests {
    @Test(arguments: SVGFile.all(in: "basic", "painting", "color"))
    func color(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "display"))
    func display(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "fill"))
    func fill(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "fill-opacity"))
    func fillOpacity(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "opacity"))
    func opacity(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "stroke-opacity"))
    func strokeOpacity(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "painting", "visibility"))
    func visibility(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
