import Testing

extension SnapshotTests {
  @MainActor
  @Suite
  struct SVGUIViewShapesTests {
    @Test(arguments: SVGFile.all(in: "basic", "shapes", "circle"))
    func circle(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "shapes", "ellipse"))
    func ellipse(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "shapes", "line"))
    func line(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "shapes", "path"))
    func path(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "shapes", "polygon"))
    func polygon(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "shapes", "polyline"))
    func polyline(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }

    @Test(arguments: SVGFile.all(in: "basic", "shapes", "rect"))
    func rect(_ file: SVGFile) async throws {
      try await assertSVGSnapshot(of: file)
    }
  }
}
